defmodule CampfireWeb.RoomLive do
  @moduledoc """
  A room: the message stream, the composer, typing indicator, presence and the involvement bell
  (docs/analysis/03-ui.md §1.5). `/rooms/:id/@:message_id` opens the page around a message.
  """
  use CampfireWeb, :live_view

  alias Campfire.{Accounts, Broadcast, Chat, Presence, Uploads}
  alias Campfire.Chat.Message
  alias CampfireWeb.{MessageComponents, RoomComponents, Sidebar}

  on_mount Sidebar

  @loads [:creator, boosts: [:booster]]
  @page_size Message.page_size()
  # The DOM keeps at most this many messages (like the original Campfire, which trims to ~300)
  @max_messages 300
  @typing_timeout 5_000

  @shared_involvements [:mentions, :everything, :nothing, :invisible]
  @direct_involvements [:everything, :nothing]

  @involvement_labels %{
    mentions: "Notifying about @ mentions",
    everything: "Notifying about all messages",
    nothing: "Notifications are off",
    invisible: "Notifications are off and room invisible in sidebar"
  }

  @impl true
  def mount(params, _session, socket) do
    user = socket.assigns.current_user

    with {id, ""} <- Integer.parse(params["id"] || ""),
         {:ok, room} <- Chat.get_room_with_members(id, actor: user) do
      {:ok, mount_room(socket, room, params["message_id"])}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, "That room doesn't exist or you don't have access to it.")
         |> push_navigate(to: ~p"/")}
    end
  end

  defp mount_room(socket, room, message_id) do
    user = socket.assigns.current_user
    {:ok, membership} = Chat.get_membership(room.id, actor: user)

    if connected?(socket) do
      Broadcast.subscribe_room(room.id)
      Broadcast.subscribe_typing(room.id)
      # Only when it changes: the update bumps users.updated_at
      if user.last_room_id != room.id, do: Accounts.set_last_room(user, room.id, actor: user)
    end

    socket
    |> assign(
      room: room,
      membership: membership,
      current_room_id: room.id,
      users: Map.new(room.users, &{&1.id, &1}),
      page_title: Sidebar.room_name(room, user),
      typing: %{},
      present?: false,
      editing_id: nil,
      boosting_id: nil
    )
    |> assign(RoomComponents.room_assigns(room, user))
    |> allow_upload(:attachments,
      accept: :any,
      max_entries: 10,
      max_file_size: 100_000_000,
      auto_upload: true
    )
    |> stream_configure(:messages, dom_id: &"messages-#{&1.client_message_id}")
    |> load_first_page(parse_id(message_id))
    |> track_presence()
  end

  defp parse_id(nil), do: nil

  defp parse_id(id) do
    case Integer.parse(id) do
      {id, ""} -> id
      _ -> nil
    end
  end

  ## Pages

  defp load_first_page(socket, nil), do: load_last_page(socket)

  defp load_first_page(socket, message_id) do
    page = page(socket, %{around: message_id})

    case Enum.find_index(page, &(&1.id == message_id)) do
      nil ->
        load_last_page(socket)

      index ->
        socket
        |> assign(highlight_id: message_id)
        |> assign_page(page, index >= @page_size, length(page) - index - 1 >= @page_size)
        |> stream(:messages, page, reset: true)
    end
  end

  defp load_last_page(socket) do
    page = page(socket, %{})

    socket
    |> assign(highlight_id: nil)
    |> assign_page(page, length(page) >= @page_size, false)
    |> stream(:messages, page, reset: true)
  end

  defp assign_page(socket, page, more_older?, more_newer?) do
    socket
    |> assign(more_older?: more_older?, more_newer?: more_newer?)
    |> put_window(Enum.map(page, & &1.id))
  end

  # The window is the ascending ids of the messages in the stream (at most @max_messages, so it's
  # cheap to keep), a `:queue` with the oldest at the front: every viewer of a room appends each new
  # message to it, which must not copy the whole window. Streams don't keep items on the server, so
  # this is how we know which messages are in the DOM. The paging cursors always point at its two
  # ends: `load_older` pages before `oldest_id` and `load_newer` after `newest_id`, which also
  # brings back whatever was trimmed.
  defp put_window(socket, ids) when is_list(ids), do: put_window(socket, :queue.from_list(ids))

  defp put_window(socket, queue) do
    assign(socket, loaded_ids: queue, oldest_id: first_id(queue), newest_id: last_id(queue))
  end

  defp first_id(queue), do: queue |> :queue.peek() |> peeked_id()
  defp last_id(queue), do: queue |> :queue.peek_r() |> peeked_id()
  defp peeked_id({:value, id}), do: id
  defp peeked_id(:empty), do: nil

  # Adds messages (ascending, newer than the whole window) at the bottom, trimming the oldest ones
  # off the top. Anything trimmed makes `more_older?` true.
  defp append_messages(socket, []), do: socket

  defp append_messages(socket, messages) do
    window = Enum.reduce(messages, socket.assigns.loaded_ids, &:queue.in(&1.id, &2))
    excess = :queue.len(window) - @max_messages
    trimmed? = excess > 0

    {_trimmed, window} =
      if trimmed?, do: :queue.split(excess, window), else: {:queue.new(), window}

    socket
    # the cursors: the front of the window, and the message added last
    |> assign(loaded_ids: window, oldest_id: first_id(window), newest_id: List.last(messages).id)
    |> update(:more_older?, &(&1 or trimmed?))
    |> stream(:messages, Enum.map(messages, &decorate(socket, &1)), limit: -@max_messages)
  end

  # Adds messages (ascending, older than the whole window) at the top, trimming the newest ones off
  # the bottom. Anything trimmed makes `more_newer?` true.
  defp prepend_messages(socket, []), do: socket

  defp prepend_messages(socket, messages) do
    window =
      messages
      |> Enum.reverse()
      |> Enum.reduce(socket.assigns.loaded_ids, &:queue.in_r(&1.id, &2))

    trimmed? = :queue.len(window) > @max_messages

    {window, _trimmed} =
      if trimmed?, do: :queue.split(@max_messages, window), else: {window, :queue.new()}

    socket
    |> put_window(window)
    |> update(:more_newer?, &(&1 or trimmed?))
    # Each item is inserted at index 0 in turn, so insert newest first to end up ascending
    |> stream(:messages, messages |> Enum.map(&decorate(socket, &1)) |> Enum.reverse(),
      at: 0,
      limit: @max_messages
    )
  end

  # Takes a deleted message out of the window: the stream limit counts DOM items, so the ids must
  # not outlive them
  defp drop_message(socket, message) do
    window = socket.assigns.loaded_ids

    socket =
      if :queue.member(message.id, window) do
        rest = :queue.delete(message.id, window)

        # Keep the cursors if nothing is left, an empty window can't be paged from
        if :queue.is_empty(rest),
          do: assign(socket, loaded_ids: rest),
          else: put_window(socket, rest)
      else
        socket
      end

    stream_delete(socket, :messages, message)
  end

  defp page(socket, cursor) do
    Chat.page_messages!(socket.assigns.room.id, cursor, actor: socket.assigns.current_user)
  end

  # Whether a message is in the stream (the trimmed window, not everything ever loaded)
  defp loaded?(socket, message), do: :queue.member(message.id, socket.assigns.loaded_ids)

  ## Presence

  defp track_presence(socket) do
    %{room: room, current_user: user, membership: membership} = socket.assigns

    if connected?(socket) and not socket.assigns.present? do
      Presence.track_user(self(), room.id, user.id)
      if membership, do: Chat.mark_read(membership, actor: user)
      assign(socket, present?: true)
    else
      socket
    end
  end

  defp untrack_presence(socket) do
    %{room: room, current_user: user} = socket.assigns

    if socket.assigns.present? do
      Presence.untrack_user(self(), room.id, user.id)
      assign(socket, present?: false)
    else
      socket
    end
  end

  ## Events: scrolling and presence

  @impl true
  def handle_event("load_older", _params, %{assigns: %{more_older?: true}} = socket) do
    older = page(socket, %{before: socket.assigns.oldest_id})

    socket =
      socket
      |> assign(more_older?: length(older) >= @page_size)
      |> prepend_messages(older)

    {:noreply, socket}
  end

  def handle_event("load_older", _params, socket), do: {:noreply, socket}

  def handle_event("load_newer", _params, %{assigns: %{more_newer?: true}} = socket) do
    newer = page(socket, %{after: socket.assigns.newest_id})

    socket =
      socket
      |> assign(more_newer?: length(newer) >= @page_size)
      |> append_messages(newer)

    {:noreply, socket}
  end

  def handle_event("load_newer", _params, socket), do: {:noreply, socket}

  def handle_event("visible", _params, socket), do: {:noreply, track_presence(socket)}
  def handle_event("hidden", _params, socket), do: {:noreply, untrack_presence(socket)}

  ## Events: composer

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :attachments, ref)}
  end

  def handle_event("typing", _params, socket) do
    broadcast_typing(socket, :start)
    {:noreply, socket}
  end

  # The composer lost focus or was emptied
  def handle_event("stop_typing", _params, socket) do
    broadcast_typing(socket, :stop)
    {:noreply, socket}
  end

  # `@` autocomplete in the composer (Composer hook): the room's members matching what was typed
  # after the `@`. Only members of this room are offered, and only to a member of it.
  def handle_event("mention_search", %{"query" => query}, socket) when is_binary(query) do
    {:reply, %{users: mention_matches(socket, query)}, socket}
  end

  def handle_event("send", params, socket) do
    body = params |> Map.get("body", "") |> String.trim_trailing()

    socket = if socket.assigns.more_newer?, do: load_last_page(socket), else: socket
    {socket, attachment_errors} = send_attachments(socket)
    text_error = if String.trim(body) == "", do: nil, else: send_text(socket, body)
    broadcast_typing(socket, :stop)

    socket =
      if attachment_errors == 0 and is_nil(text_error) do
        push_event(socket, "composer:reset", %{})
      else
        put_flash(socket, :error, "Your message couldn't be sent.")
      end

    {:noreply, socket}
  end

  def handle_event("edit_last", _params, socket) do
    user = socket.assigns.current_user
    # The last messages must be the ones in the stream, not an older window
    socket = if socket.assigns.more_newer?, do: load_last_page(socket), else: socket

    case socket |> page(%{}) |> Enum.filter(&(&1.creator_id == user.id)) |> List.last() do
      nil -> {:noreply, socket}
      message -> {:noreply, start_editing(socket, message)}
    end
  end

  ## Events: message actions

  def handle_event("play_sound", %{"url" => url}, socket) do
    {:noreply, push_event(socket, "play_sound", %{url: url})}
  end

  def handle_event("reply", %{"id" => id}, socket) do
    with_message(socket, id, fn message ->
      # "> quote\n— Author /rooms/1/@123\n\n" (rendered as blockquote + cite by MessageBody)
      push_event(socket, "composer:insert", %{text: CampfireWeb.MessageBody.reply_text(message)})
    end)
  end

  def handle_event("edit", %{"id" => id}, socket) do
    with_message(socket, id, &start_editing(socket, &1))
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, put_form(socket, :editing_id, nil)}
  end

  def handle_event("update_message", %{"message_id" => id, "body" => body}, socket) do
    with_message(socket, id, fn message ->
      case Chat.update_message(message, %{body: body}, actor: socket.assigns.current_user) do
        {:ok, message} -> socket |> close_form(:editing_id, message) |> insert_message(message)
        {:error, error} -> put_flash(socket, :error, error_message(error, "edit"))
      end
    end)
  end

  def handle_event("delete_message", %{"id" => id}, socket) do
    with_message(socket, id, fn message ->
      case Chat.destroy_message(message, actor: socket.assigns.current_user) do
        :ok -> drop_message(socket, message)
        {:error, error} -> put_flash(socket, :error, error_message(error, "delete"))
      end
    end)
  end

  def handle_event("boost", %{"id" => id, "content" => content}, socket) do
    create_boost(socket, id, content)
  end

  def handle_event("save_boost", %{"message_id" => id, "content" => content}, socket) do
    create_boost(socket, id, content)
  end

  def handle_event("new_boost", %{"id" => id}, socket) do
    with_message(socket, id, &put_form(socket, :boosting_id, &1))
  end

  def handle_event("cancel_boost", _params, socket) do
    {:noreply, put_form(socket, :boosting_id, nil)}
  end

  def handle_event("delete_boost", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    with {:ok, boost} <- Chat.get_boost(id, actor: user),
         :ok <- Chat.destroy_boost(boost, actor: user) do
      {:noreply, socket}
    else
      {:error, error} -> {:noreply, put_flash(socket, :error, error_message(error, "remove"))}
    end
  end

  ## Events: involvement bell

  def handle_event("toggle_involvement", _params, socket) do
    %{membership: membership, room: room, current_user: user} = socket.assigns

    case Chat.set_involvement(membership, next_involvement(room, membership.involvement),
           actor: user
         ) do
      {:ok, membership} -> {:noreply, assign(socket, membership: membership)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Couldn't change notifications.")}
    end
  end

  ## PubSub

  @impl true
  def handle_info({:message_created, message}, socket) do
    cond do
      # Scrolled back from the live end: load_newer fetches it when the user gets there
      socket.assigns.more_newer? ->
        {:noreply, socket}

      loaded?(socket, message) ->
        {:noreply, insert_message(socket, message)}

      true ->
        socket =
          socket
          |> append_messages([message])
          |> stop_typing(message.creator_id)

        {:noreply, maybe_play_sound(socket, message)}
    end
  end

  def handle_info({:message_updated, message}, socket) do
    {:noreply, insert_message(socket, message)}
  end

  def handle_info({:message_deleted, message}, socket) do
    {:noreply, drop_message(socket, message)}
  end

  # The broadcast carries the message with its boosts, read once for every viewer
  # (`Campfire.PubSubBroadcaster`); nil when the message was deleted meanwhile
  def handle_info({event, %{message: %Message{} = message}}, socket)
      when event in [:boost_created, :boost_deleted] do
    {:noreply, insert_message(socket, message)}
  end

  def handle_info({:typing, :start, %{id: id, name: name}}, socket) do
    ref = make_ref()
    Process.send_after(self(), {:typing_expired, id, ref}, @typing_timeout)
    {:noreply, update(socket, :typing, &Map.put(&1, id, {name, ref}))}
  end

  def handle_info({:typing, :stop, %{id: id}}, socket), do: {:noreply, stop_typing(socket, id)}

  def handle_info({:typing_expired, id, ref}, socket) do
    case socket.assigns.typing do
      %{^id => {_name, ^ref}} -> {:noreply, stop_typing(socket, id)}
      _ -> {:noreply, socket}
    end
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  ## Helpers

  defp with_message(socket, id, fun) do
    case Chat.get_message(id, actor: socket.assigns.current_user, load: @loads) do
      {:ok, %{room_id: room_id} = message} when room_id == socket.assigns.room.id ->
        {:noreply, fun.(message)}

      _ ->
        {:noreply, put_flash(socket, :error, "That message no longer exists.")}
    end
  end

  defp start_editing(socket, message) do
    if MessageComponents.can_edit?(socket.assigns.current_user, message) do
      put_form(socket, :editing_id, message)
    else
      put_flash(socket, :error, "You can't edit that message.")
    end
  end

  # Re-renders a message that's in the stream, in place: the window and the stream limit don't
  # change. Messages outside the window are ignored (new ones go through append_messages/2).
  defp insert_message(socket, message) do
    if loaded?(socket, message),
      do: stream_insert(socket, :messages, decorate(socket, message)),
      else: socket
  end

  # Every message put in the stream goes through here, so one re-inserted on an update or a boost
  # keeps the user's open edit or custom boost form
  defp decorate(socket, message) do
    %{editing_id: editing_id, boosting_id: boosting_id} = socket.assigns

    message
    |> Ash.Resource.put_metadata(:editing, message.id == editing_id)
    |> Ash.Resource.put_metadata(:boosting, message.id == boosting_id)
  end

  # Opens the edit (`:editing_id`) or custom boost (`:boosting_id`) form on `message`, or closes it
  # with `nil`. One of each is open at a time: the message whose form was open is re-inserted so
  # its form goes away (otherwise it stays rendered, and Escape cancels both).
  defp put_form(socket, key, message) do
    previous_id = socket.assigns[key]
    id = message && message.id
    socket = assign(socket, key, id)

    socket =
      if previous_id && previous_id != id,
        do: reinsert_message(socket, previous_id),
        else: socket

    if message, do: insert_message(socket, message), else: socket
  end

  # Clears the form state when it belongs to `message` (which the caller re-inserts or which comes
  # back through PubSub)
  defp close_form(socket, key, %{id: id}) do
    if socket.assigns[key] == id, do: assign(socket, key, nil), else: socket
  end

  # Re-fetches a message and re-inserts it if it's still visible to the user and in the window
  defp reinsert_message(socket, id) do
    case Chat.get_message(id, actor: socket.assigns.current_user, load: @loads) do
      {:ok, %{room_id: room_id} = message} when room_id == socket.assigns.room.id ->
        insert_message(socket, message)

      _ ->
        socket
    end
  end

  defp create_boost(socket, id, content) do
    with_message(socket, id, fn message ->
      case Chat.create_boost(message, content, actor: socket.assigns.current_user) do
        {:ok, _boost} -> close_form(socket, :boosting_id, message)
        {:error, error} -> put_flash(socket, :error, error_message(error, "boost"))
      end
    end)
  end

  defp send_text(socket, body) do
    %{room: room, current_user: user} = socket.assigns

    case Chat.create_message(room, %{body: body}, actor: user) do
      {:ok, _message} -> nil
      {:error, error} -> error
    end
  end

  # Each uploaded file becomes its own message. Returns the socket and the number of failures.
  defp send_attachments(socket) do
    %{room: room, current_user: user} = socket.assigns
    done = Enum.filter(socket.assigns.uploads.attachments.entries, & &1.done?)

    results =
      for entry <- done do
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          content_type =
            Uploads.normalize_content_type(entry.client_type) || MIME.from_path(entry.client_name)

          # Dimensions and a thumbnail for raster images; best effort, never fails the upload
          image = Uploads.Image.attributes(path, content_type)

          with {:ok, key} <- Uploads.store(path, entry.client_name),
               attrs =
                 Map.merge(image, %{
                   attachment_key: key,
                   attachment_filename: entry.client_name,
                   attachment_content_type: content_type,
                   attachment_byte_size: entry.client_size
                 }),
               {:ok, message} <- Chat.create_message(room, attrs, actor: user) do
            {:ok, {:ok, message}}
          else
            error ->
              Uploads.delete(image[:attachment_thumbnail_key])
              {:ok, error}
          end
        end)
      end

    {socket, Enum.count(results, &(not match?({:ok, _}, &1)))}
  end

  defp maybe_play_sound(socket, message) do
    case Message.sound_name(message) do
      nil -> socket
      name -> push_event(socket, "play_sound", %{url: Campfire.Sound.audio_path(name)})
    end
  end

  defp broadcast_typing(socket, action) do
    %{room: room, current_user: user} = socket.assigns

    Phoenix.PubSub.broadcast_from(
      Campfire.PubSub,
      self(),
      Broadcast.typing_topic(room.id),
      {:typing, action, %{id: user.id, name: user.name}}
    )
  end

  defp stop_typing(socket, user_id), do: update(socket, :typing, &Map.delete(&1, user_id))

  @mention_limit 8

  # Members whose name, or any word of it, starts with `query` (case-insensitive), by name
  defp mention_matches(%{assigns: %{membership: nil}}, _query), do: []

  defp mention_matches(socket, query) do
    query = query |> String.slice(0, 50) |> String.trim_leading() |> String.downcase()

    socket.assigns.users
    |> Map.values()
    |> Enum.filter(fn user ->
      name = String.downcase(user.name)
      String.starts_with?(name, query) or String.contains?(name, " " <> query)
    end)
    |> Enum.sort_by(&{String.downcase(&1.name), &1.id})
    |> Enum.take(@mention_limit)
    |> Enum.map(&%{id: &1.id, name: &1.name, avatar: CampfireWeb.Paths.avatar_path(&1)})
  end

  defp next_involvement(room, current) do
    order = if room.kind == :direct, do: @direct_involvements, else: @shared_involvements
    index = Enum.find_index(order, &(&1 == current)) || -1
    Enum.at(order, index + 1) || hd(order)
  end

  defp error_message(%Ash.Error.Forbidden{}, verb), do: "You can't #{verb} that."
  defp error_message(_error, verb), do: "Couldn't #{verb} that."

  defp typing_names(typing) do
    typing |> Map.values() |> Enum.map(&elem(&1, 0)) |> Enum.sort() |> Enum.join(", ")
  end

  ## Render

  @impl true
  def render(assigns) do
    assigns = assign(assigns, involvement_labels: @involvement_labels)

    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <:nav>
        <RoomComponents.nav_logo account={@account} />

        <span class="btn btn--reversed btn--faux room--current">
          <h1 class="room__contents txt-medium overflow-ellipsis">
            <span :if={@room.kind == :direct} class="for-screen-reader">Ping with</span>
            {@page_title}
          </h1>
        </span>

        <.icon_button
          icon="menu-dots-horizontal"
          label={"Settings for this #{if @room.kind == :direct, do: "Ping", else: "room"}"}
          navigate={~p"/rooms/#{@room.id}/edit"}
        />

        <button
          :if={@membership}
          id="involvement"
          type="button"
          class={["btn", to_string(@membership.involvement)]}
          role="checkbox"
          aria-checked="true"
          phx-click="toggle_involvement"
        >
          <img
            src={icon_path("notification-bell-#{@membership.involvement}")}
            width="20"
            height="20"
            aria-hidden="true"
          />
          <span class="for-screen-reader">{@involvement_labels[@membership.involvement]}</span>
        </button>
      </:nav>

      <div
        id="message-area"
        class="message-area"
        phx-hook="Lightbox"
        phx-drop-target={@uploads.attachments.ref}
      >
        <%!-- The pager (MessagePager hook) loads older/newer pages on scroll. It's an empty, absolutely
             positioned element (so it takes no grid row) and not the stream: LiveView's own
             `phx-viewport-*` hook locks the element it pushes from while an event is in flight, and
             overlapping locked stream patches come out in the wrong order. --%>
        <div id={"room_#{@room.id}_messages"} class="messages" phx-hook="MessageList">
          <div
            id={"room_#{@room.id}_message_pager"}
            phx-hook="MessagePager"
            data-load-older={@more_older? && "load_older"}
            data-load-newer={@more_newer? && "load_newer"}
            style="position: absolute; inset-block-start: 0; block-size: 0; inline-size: 0"
            aria-hidden="true"
          >
          </div>
          <RoomComponents.system_welcome
            :if={
              RoomComponents.show_welcome?(
                @original_room?,
                @account,
                @more_older?,
                @more_newer?,
                :queue.len(@loaded_ids)
              )
            }
            account={@account}
            invite_url={@invite_url}
          />
          <div id={"room_#{@room.id}_message_stream"} phx-update="stream" style="display: contents">
            <MessageComponents.cached_message
              :for={{dom_id, message} <- @streams.messages}
              id={dom_id}
              message={message}
              current_user={@current_user}
              users={@users}
              highlighted={message.id == @highlight_id}
            />
          </div>
        </div>

        <button type="button" class="message-area__return-to-latest btn" hidden>
          <img src={~p"/images/arrow-down.svg"} width="20" height="20" aria-hidden="true" />
          <span class="for-screen-reader">Jump to newest message</span>
        </button>
      </div>

      <div id="visibility" phx-hook="Visibility" hidden></div>

      <:footer>
        <.composer room_id={@room.id} uploads={@uploads} typing={typing_names(@typing)} />
      </:footer>

      <:sidebar>
        <Sidebar.sidebar
          sidebar={@sidebar}
          current_user={@current_user}
          current_room_id={@current_room_id}
        />
      </:sidebar>
    </Layouts.app>
    """
  end

  # The formatting toolbar (composer_toolbar.js): {format, label, icon}, the icon being a monochrome
  # SVG file in priv/static/images. Shown by the rich text button.
  defp format_buttons do
    [
      {"bold", "Bold", "format-bold.svg"},
      {"italic", "Italic", "format-italic.svg"},
      {"strike", "Strikethrough", "format-strike.svg"},
      {"highlight", "Highlight", "format-highlight.svg"},
      {"code", "Code", "format-code.svg"},
      {"codeblock", "Code block", "format-code-block.svg"},
      {"heading", "Heading", "format-heading.svg"},
      {"quote", "Quote", "format-quote.svg"},
      {"bullet", "Bulleted list", "format-bullets.svg"},
      {"number", "Numbered list", "format-numbers.svg"},
      {"link", "Link", "link.svg"}
    ]
  end

  attr :uploads, :map, required: true
  attr :typing, :string, default: ""
  attr :room_id, :integer, required: true

  defp composer(assigns) do
    ~H"""
    <div class="composer flex align-end gap position-relative">
      <.icon_button
        icon="search"
        label="Search"
        navigate={~p"/searches"}
        class="flex-item-no-shrink margin-block-end composer__context-btn"
      />

      <form
        id="composer"
        class="margin-block flex-item-grow contain"
        phx-submit="send"
        phx-change="validate"
        phx-drop-target={@uploads.attachments.ref}
      >
        <fieldset contents>
          <div class="flex flex-column">
            <div class="composer__filelist flex flex--align-center gap flex-wrap">
              <button
                :for={entry <- @uploads.attachments.entries}
                type="button"
                class="btn composer__file"
                style={"--percentage: #{entry.progress}%"}
                title={upload_title(@uploads.attachments, entry)}
                phx-click="cancel_upload"
                phx-value-ref={entry.ref}
              >
                <.live_img_preview
                  :if={String.starts_with?(entry.client_type, "image/")}
                  entry={entry}
                  class="composer__file-thumbnail"
                />
                <span
                  :if={!String.starts_with?(entry.client_type, "image/")}
                  class="composer__file-thumbnail composer__file-thumbnail--common"
                ></span>
                <span class="composer__file-caption flex align-center txt-small overflow-ellipsis">
                  {entry.client_name}{if entry.progress < 100, do: " (#{entry.progress}%)"}
                </span>
              </button>
            </div>

            <div
              class="flex composer__input input input--actor fill-white min-width"
              style="--input-border-radius: 1.3rem"
            >
              <div class="flex align-end gap full-width">
                <img
                  src={~p"/images/messages-outlined.svg"}
                  width="22"
                  height="22"
                  class="composer__input-hint colorize--black"
                  aria-hidden="true"
                />

                <div class="flex flex-column flex-item-grow min-width gap">
                  <textarea
                    id="composer-body"
                    name="body"
                    rows="1"
                    class="input"
                    aria-label="Write a message"
                    placeholder="Write a message…"
                    phx-hook="Composer"
                    phx-debounce="blur"
                    data-room-id={@room_id}
                    data-mention-menu="composer-mentions"
                    data-toolbar="composer-toolbar"
                    data-toolbar-toggle="composer-toolbar-toggle"
                  ></textarea>

                  <%!-- Formatting toolbar: opened by the rich text button, its state kept by the Composer hook --%>
                  <div
                    id="composer-toolbar"
                    class="composer__toolbar"
                    role="toolbar"
                    aria-label="Text formatting"
                    phx-update="ignore"
                    hidden
                  >
                    <button
                      :for={{format, label, icon} <- format_buttons()}
                      type="button"
                      class="btn btn--borderless composer__format-btn"
                      data-format={format}
                      title={label}
                      aria-label={label}
                    >
                      <img src={~p"/images/#{icon}"} width="20" height="20" aria-hidden="true" />
                    </button>
                  </div>
                </div>

                <label class="btn btn--borderless txt-small flex-item-no-shrink composer__attachment-btn input--file">
                  <img
                    src={~p"/images/attachment.svg"}
                    width="22"
                    height="22"
                    class="colorize--black"
                    aria-hidden="true"
                  />
                  <.live_file_input upload={@uploads.attachments} />
                  <span class="for-screen-reader">Attach a file</span>
                </label>

                <button
                  id="composer-toolbar-toggle"
                  type="button"
                  class="btn btn--borderless txt-small flex-item-no-shrink composer__rich-text-btn"
                  aria-controls="composer-toolbar"
                  aria-expanded="false"
                  phx-update="ignore"
                >
                  <img
                    src={~p"/images/text-options.svg"}
                    width="20"
                    height="20"
                    class="colorize--black"
                    aria-hidden="true"
                  />
                  <span class="for-screen-reader">Rich text</span>
                </button>

                <button type="submit" class="btn btn--reversed flex-item-no-shrink txt-small">
                  <img src={~p"/images/arrow-up.svg"} width="20" height="20" aria-hidden="true" />
                  <span class="for-screen-reader">Send Message</span>
                </button>
              </div>
            </div>
          </div>
        </fieldset>

        <div class={[
          "typing-indicator gap txt-small align-center flex-inline",
          @typing != "" && "typing-indicator--active"
        ]}>
          <div class="typing-indicator__author spinner">{@typing}</div>
        </div>
      </form>

      <%!-- The @ mention menu, filled in by the Composer hook (so LiveView leaves it alone) --%>
      <div
        id="composer-mentions"
        class="autocomplete__list composer__mentions"
        role="listbox"
        aria-label="Mention a member"
        phx-update="ignore"
        hidden
      >
      </div>
    </div>
    """
  end

  defp upload_title(upload, entry) do
    case upload_errors(upload, entry) do
      [] -> entry.client_name
      errors -> Enum.map_join(errors, ", ", &upload_error/1)
    end
  end

  defp upload_error(:too_large), do: "Too large (100 MB max)"
  defp upload_error(:too_many_files), do: "Too many files (10 max)"
  defp upload_error(error), do: to_string(error)
end
