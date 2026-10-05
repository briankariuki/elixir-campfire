defmodule CampfireWeb.RoomLive do
  @moduledoc """
  A room: the message stream, the composer, typing indicator, presence and the involvement bell
  (docs/analysis/03-ui.md §1.5). `/rooms/:id/@:message_id` opens the page around a message.
  """
  use CampfireWeb, :live_view

  alias Campfire.{Accounts, Broadcast, Chat, Presence, Uploads}
  alias Campfire.Chat.Message
  alias CampfireWeb.{MessageComponents, Sidebar}

  on_mount Sidebar

  @loads [:creator, boosts: [:booster]]
  @page_size Message.page_size()
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
         {:ok, room} <- Chat.get_room(id, actor: user, load: [:users]) do
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
      Accounts.set_last_room(user, room.id, actor: user)
    end

    socket
    |> assign(
      room: room,
      membership: membership,
      current_room_id: room.id,
      users: Map.new(room.users, &{&1.id, &1}),
      page_title: Sidebar.room_name(room, user),
      body_class: "sidebar",
      typing: %{},
      present?: false
    )
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
    assign(socket,
      oldest_id: page |> List.first() |> then(&(&1 && &1.id)),
      newest_id: page |> List.last() |> then(&(&1 && &1.id)),
      more_older?: more_older?,
      more_newer?: more_newer?
    )
  end

  defp page(socket, cursor) do
    Chat.page_messages!(socket.assigns.room.id, cursor, actor: socket.assigns.current_user)
  end

  # Whether a message falls in the range of messages loaded in the stream
  defp loaded?(socket, message) do
    %{oldest_id: oldest, newest_id: newest, more_newer?: more_newer?} = socket.assigns

    (is_nil(oldest) or message.id >= oldest) and
      (not more_newer? or is_nil(newest) or message.id <= newest)
  end

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
      |> assign(oldest_id: if(older == [], do: socket.assigns.oldest_id, else: hd(older).id))
      |> stream(:messages, Enum.reverse(older), at: 0)

    {:noreply, socket}
  end

  def handle_event("load_older", _params, socket), do: {:noreply, socket}

  def handle_event("load_newer", _params, %{assigns: %{more_newer?: true}} = socket) do
    newer = page(socket, %{after: socket.assigns.newest_id})

    socket =
      socket
      |> assign(more_newer?: length(newer) >= @page_size)
      |> assign(
        newest_id: if(newer == [], do: socket.assigns.newest_id, else: List.last(newer).id)
      )
      |> stream(:messages, newer)

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
      quoted =
        message.body
        |> String.split(~r/\r?\n/)
        |> Enum.reject(&String.starts_with?(&1, ">"))
        |> Enum.map_join("\n", &"> #{&1}")

      push_event(socket, "composer:insert", %{text: quoted <> "\n"})
    end)
  end

  def handle_event("edit", %{"id" => id}, socket) do
    with_message(socket, id, &start_editing(socket, &1))
  end

  def handle_event("cancel_edit", %{"id" => id}, socket) do
    with_message(socket, id, &stream_insert(socket, :messages, &1))
  end

  def handle_event("cancel_edit", _params, socket), do: {:noreply, socket}

  def handle_event("update_message", %{"message_id" => id, "body" => body}, socket) do
    with_message(socket, id, fn message ->
      case Chat.update_message(message, %{body: body}, actor: socket.assigns.current_user) do
        {:ok, message} -> stream_insert(socket, :messages, message)
        {:error, error} -> put_flash(socket, :error, error_message(error, "edit"))
      end
    end)
  end

  def handle_event("delete_message", %{"id" => id}, socket) do
    with_message(socket, id, fn message ->
      case Chat.destroy_message(message, actor: socket.assigns.current_user) do
        :ok -> stream_delete(socket, :messages, message)
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
    with_message(socket, id, fn message ->
      stream_insert(socket, :messages, Ash.Resource.put_metadata(message, :boosting, true))
    end)
  end

  def handle_event("cancel_boost", %{"id" => id}, socket) do
    with_message(socket, id, &stream_insert(socket, :messages, &1))
  end

  def handle_event("cancel_boost", _params, socket), do: {:noreply, socket}

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
    if socket.assigns.more_newer? do
      {:noreply, socket}
    else
      socket =
        socket
        |> assign(newest_id: max(message.id, socket.assigns.newest_id || 0))
        |> assign(oldest_id: socket.assigns.oldest_id || message.id)
        |> stream_insert(:messages, message)
        |> stop_typing(message.creator_id)

      {:noreply, maybe_play_sound(socket, message)}
    end
  end

  def handle_info({:message_updated, message}, socket) do
    if loaded?(socket, message),
      do: {:noreply, stream_insert(socket, :messages, message)},
      else: {:noreply, socket}
  end

  def handle_info({:message_deleted, message}, socket) do
    {:noreply, stream_delete(socket, :messages, message)}
  end

  def handle_info({event, boost}, socket) when event in [:boost_created, :boost_deleted] do
    case Chat.get_message(boost.message_id, actor: socket.assigns.current_user, load: @loads) do
      {:ok, message} ->
        if loaded?(socket, message),
          do: {:noreply, stream_insert(socket, :messages, message)},
          else: {:noreply, socket}

      {:error, _} ->
        {:noreply, socket}
    end
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
      stream_insert(socket, :messages, Ash.Resource.put_metadata(message, :editing, true))
    else
      put_flash(socket, :error, "You can't edit that message.")
    end
  end

  defp create_boost(socket, id, content) do
    with_message(socket, id, fn message ->
      case Chat.create_boost(message, content, actor: socket.assigns.current_user) do
        {:ok, _boost} -> socket
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
          with {:ok, key} <- Uploads.store(path, entry.client_name),
               {:ok, message} <-
                 Chat.create_message(
                   room,
                   %{
                     attachment_key: key,
                     attachment_filename: entry.client_name,
                     attachment_content_type: entry.client_type,
                     attachment_byte_size: entry.client_size
                   },
                   actor: user
                 ) do
            {:ok, {:ok, message}}
          else
            error -> {:ok, error}
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
        <%!-- LiveView's own infinite-scroll hook takes over the element with phx-viewport-*, so the
             stream lives in an inner (display: contents) element and MessageList on the scroller --%>
        <div id={"room_#{@room.id}_messages"} class="messages" phx-hook="MessageList">
          <div
            id={"room_#{@room.id}_message_stream"}
            phx-update="stream"
            phx-viewport-top={@more_older? && "load_older"}
            phx-viewport-bottom={@more_newer? && "load_newer"}
            style="display: contents"
          >
            <MessageComponents.message
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
        <.composer uploads={@uploads} typing={typing_names(@typing)} />
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

  attr :uploads, :map, required: true
  attr :typing, :string, default: ""

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
                  ></textarea>
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
