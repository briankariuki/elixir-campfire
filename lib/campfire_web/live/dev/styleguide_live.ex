defmodule CampfireWeb.Dev.StyleguideLive do
  @moduledoc """
  Development-only page (`/dev/styleguide`) with fake data, to visually check the CSS port, the
  layout, the core components and the JS hooks. Uses the original Campfire markup.

  `/dev/styleguide` shows a room (sidebar, messages, composer); `?view=components` shows a settings
  panel with forms, buttons, switches and avatars.
  """
  use CampfireWeb, :live_view

  @me %{id: 1, name: "Brian Kariuki", bio: "Here for the sounds"}
  @david %{id: 2, name: "David Heinemeier", bio: "Creator of Ruby on Rails"}
  @jason %{id: 3, name: "Jason Fried", bio: nil}
  @bot %{id: 4, name: "Deploy Bot", bio: nil}

  @avatar_colors ~w(#AF2E1B #CC6324 #3B4B59 #BFA07A #ED8008 #ED3F1C #BF1B1B #736B1E #D07B53
                    #736356 #AD1D1D #BF7C2A #C09C6F #698F9C #7C956B #5D618F #3B3633 #67695E)

  @impl true
  def mount(params, _session, socket) do
    view = if is_map(params) and params["view"] == "components", do: :components, else: :room

    {:ok,
     socket
     |> assign(page_title: "Styleguide", view: view, me: @me, typing: nil)
     |> assign(david: @david, jason: @jason, bot: @bot)
     |> assign(body_class: if(view == :room, do: "sidebar"))
     |> assign(form: to_form(%{"name" => "Campfire", "email" => "", "restrict" => "true"}))
     |> allow_upload(:attachments, accept: :any, max_entries: 10)
     |> stream(:messages, fake_messages())}
  end

  @impl true
  def handle_event("send", %{"message" => %{"body" => body}}, socket) do
    now = DateTime.utc_now()

    files =
      consume_uploaded_entries(socket, :attachments, fn _meta, entry ->
        {:ok, entry.client_name}
      end)

    messages =
      Enum.map(files, &message(System.unique_integer([:positive]), @me, now, file: &1)) ++
        if(String.trim(body) == "",
          do: [],
          else: [message(System.unique_integer([:positive]), @me, now, body: body)]
        )

    socket =
      Enum.reduce(messages, socket, &stream_insert(&2, :messages, &1))
      |> assign(typing: nil)
      |> push_event("composer:reset", %{})

    socket =
      case Regex.run(~r/\A\/play (\w+)\z/, String.trim(body)) do
        [_, name] -> push_event(socket, "play_sound", %{url: "/sounds/#{name}.mp3"})
        _ -> socket
      end

    {:noreply, socket}
  end

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :attachments, ref)}
  end

  def handle_event("typing", _params, socket) do
    Process.send_after(self(), :stop_typing, 3000)
    {:noreply, assign(socket, typing: "#{first_name(@me)} (you)")}
  end

  def handle_event("edit_last", _params, socket) do
    {:noreply, put_flash(socket, :info, "edit_last received")}
  end

  def handle_event("play", %{"url" => url}, socket) do
    {:noreply, push_event(socket, "play_sound", %{url: url})}
  end

  def handle_event("load_older", _params, socket) do
    older = DateTime.add(DateTime.utc_now(), -3, :day)
    id = System.unique_integer([:positive])
    msg = message(id, @jason, older, body: "An older message, prepended (##{id})")
    {:noreply, stream_insert(socket, :messages, msg, at: 0)}
  end

  def handle_event(event, _params, socket) when event in ~w(visible hidden) do
    {:noreply, socket}
  end

  def handle_event("save", _params, socket) do
    {:noreply, put_flash(socket, :info, "Saved")}
  end

  def handle_event("fail", _params, socket) do
    {:noreply, put_flash(socket, :error, "Something failed")}
  end

  @impl true
  def handle_info(:stop_typing, socket), do: {:noreply, assign(socket, typing: nil)}

  @impl true
  def render(%{view: :components} = assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <:nav>
        <.icon_button icon="arrow-left" label="Back" href="/dev/styleguide" />
      </:nav>

      <section class="panel panel--wide center margin-block-double flex flex-column gap">
        <h1 class="txt-large">Components</h1>

        <.form for={@form} phx-submit="save" class="flex flex-column gap">
          <.input field={@form[:name]} icon="person" placeholder="Name" class="txt-large" />
          <.input field={@form[:email]} type="email" icon="email" placeholder="Email address" />
          <.input name="password" value="" type="password" icon="password" placeholder="Password" />
          <.input name="plain" value="" placeholder="A plain .input" />
          <.input name="bio" value="" type="textarea" rows="3" label="Bio" />
          <.input name="agree" value="false" type="checkbox" label="A checkbox" />

          <div class="flex align-center gap fill-shade pad border-radius">
            <strong>👑 Must be admin to create new rooms</strong>
            <hr class="separator" />
            <.switch field={@form[:restrict]} label="Restrict room creation" />
          </div>

          <div class="flex align-center gap flex-wrap">
            <.button>Button</.button>
            <.button variant="reversed" type="submit">Reversed submit</.button>
            <.button variant="negative" phx-click="fail">Negative</.button>
            <.button variant="plain">Plain</.button>
            <.icon_button icon="check" label="Save" type="submit" variant="reversed" />
            <.icon_button icon="trash" label="Delete" variant="negative" />
            <.icon_button icon="search" label="Search" />
            <.icon_button icon="link" label="Copy" id="copy-demo" phx-hook="Copy" data-copy="hello" />
            <.input name="file" type="file" icon="camera" label="Upload" />
          </div>
        </.form>

        <div class="flex align-center gap flex-wrap">
          <.avatar src={initials_avatar(@me)} />
          <.avatar src={initials_avatar(@david)} size="10ch" />
          <.avatar src={initials_avatar(@jason)} size="3ch" navigate={~p"/"} title="Jason" />
          <.avatar src="/images/default-bot-avatar.svg" />
          <span class="banned"><.avatar src={initials_avatar(@bot)} /></span>
        </div>
      </section>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@me}>
      <:nav>
        <span class="btn btn--reversed btn--faux room--current">
          <h1 class="room__contents txt-medium overflow-ellipsis">Watercooler</h1>
        </span>
        <.icon_button
          icon="menu-dots-horizontal"
          label="Settings for this room"
          href="/dev/styleguide?view=components"
        />
        <.icon_button icon="notification-bell-mentions" label="Notifying about @ mentions" />
        <.icon_button icon="refresh" label="Prepend an older message (demo)" phx-click="load_older" />
      </:nav>

      <div id="message-area" class="message-area" phx-hook="Lightbox">
        <div
          id="messages"
          class="messages"
          phx-update="stream"
          phx-hook="MessageList"
        >
          <.demo_message :for={{dom_id, msg} <- @streams.messages} id={dom_id} message={msg} me={@me} />
        </div>

        <button class="message-area__return-to-latest btn" hidden>
          <img src="/images/arrow-down.svg" width="20" height="20" aria-hidden="true" />
          <span class="for-screen-reader">Jump to newest message</span>
        </button>
      </div>

      <div id="visibility" phx-hook="Visibility" hidden></div>

      <:footer>
        <.demo_composer uploads={@uploads} typing={@typing} />
      </:footer>

      <:sidebar>
        <.demo_sidebar me={@me} />
      </:sidebar>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :message, :map, required: true
  attr :me, :map, required: true

  defp demo_message(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "message message--formatted",
        @message.creator.id == @me.id && "message--me",
        @message.mentioned && "message--mentioned",
        @message.emoji && "message--emoji"
      ]}
      data-user-id={@message.creator.id}
      data-message-id={@message.id}
      data-message-timestamp={DateTime.to_unix(@message.at, :millisecond)}
    >
      <h2 class="message__day-separator">
        <time datetime={DateTime.to_iso8601(@message.at)} data-format="date"></time>
      </h2>

      <figure class="avatar message__avatar">
        <a class="btn avatar" href="#" title={title(@message.creator)}>
          <img src={initials_avatar(@message.creator)} width="48" height="48" aria-hidden="true" />
        </a>
      </figure>

      <div class="message__body">
        <div class="message__body-content">
          <div class="message__meta">
            <h3 class="message__heading">
              <span class="message__author" title={title(@message.creator)}>
                <strong>{@message.creator.name}</strong>
              </span>
              <a class="message__permalink" href={"#message-#{@message.id}"}>
                <time
                  class="message__timestamp"
                  datetime={DateTime.to_iso8601(@message.at)}
                  data-format="time"
                ></time>
              </a>
              <span class="message__room"><a href="#">Watercooler</a></span>
            </h3>
            <.demo_actions message={@message} />
          </div>

          <div id={"presentation-#{@message.id}"} dir="auto">
            <.demo_presentation message={@message} />
          </div>

          <div
            class="boosts flex flex-wrap align-center gap full-width"
            style="--column-gap: 0.4ch; --row-gap: 0"
          >
            <div class="flex-inline flex-wrap gap">
              <div
                :for={{booster, content} <- @message.boosts}
                class="boost boost-item flex-inline max-width align-center fill-white gap"
              >
                <figure class="avatar boost__avatar flex-item-no-shrink">
                  <a class="btn avatar" href="#">
                    <img src={initials_avatar(booster)} width="48" height="48" aria-hidden="true" />
                  </a>
                </figure>
                <span role="button" class="txt-small txt-medium">{content}</span>
              </div>
            </div>
            <div class="flex-inline message__boost-inline">
              <a class="boost__action txt-small btn" href="#">
                <img src="/images/boost.svg" width="20" height="20" aria-hidden="true" />
                <span class="for-screen-reader">Add a boost</span>
              </a>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :message, :map, required: true

  defp demo_presentation(%{message: %{file: file}} = assigns) when is_binary(file) do
    ~H"""
    <div class="flex-inline align-center gap-half">
      <img
        src="/images/common-file-text.svg"
        width="22"
        height="22"
        class="colorize--black"
        aria-hidden="true"
      />
      <span>{@message.file}</span>
    </div>
    """
  end

  defp demo_presentation(%{message: %{image: {src, w, h}}} = assigns) do
    assigns = assign(assigns, src: src, w: w, h: h)

    ~H"""
    <div
      class="max-inline-size center flex overflow-clip"
      style={"width: #{div(@w, 2)}px; aspect-ratio: #{@w / @h};"}
    >
      <a class="flex" href={@src} data-lightbox data-lightbox-download={@src}>
        <img src={@src} width={@w} height={@h} class="message__attachment" loading="lazy" />
      </a>
    </div>
    """
  end

  defp demo_presentation(%{message: %{sound: {name, display}}} = assigns) do
    assigns = assign(assigns, name: name, display: display)

    ~H"""
    <div class="sound">
      <button class="btn btn--plain" phx-click="play" phx-value-url={"/sounds/#{@name}.mp3"}>
        🔊
      </button>
      <%= case @display do %>
        <% {:image, file, w, h} -> %>
          <img src={"/images/sounds/#{file}"} width={w} height={h} class="align--middle" />
        <% text -> %>
          {text}
      <% end %>
    </div>
    """
  end

  defp demo_presentation(assigns) do
    ~H"""
    <div class="lexxy-content">{@message.html}</div>
    """
  end

  attr :message, :map, required: true

  defp demo_actions(assigns) do
    ~H"""
    <div class="message__actions">
      <details class="position-relative">
        <summary class="btn message__action-btn message__options-btn">
          <img
            src="/images/menu-dots-horizontal.svg"
            width="20"
            height="20"
            class="colorize--black"
            aria-hidden="true"
          />
          <span class="for-screen-reader">Message options</span>
        </summary>

        <div class="message__actions-menu border shadow">
          <div class="quick-boosts">
            <button
              :for={emoji <- ~w(👍 👏 👋 💪 ❤️ 😂 🎉 🔥)}
              type="button"
              class="btn message__action-btn"
            >
              <figure class="margin-none boost-character">{emoji}</figure>
              <span class="for-screen-reader">Boost with {emoji}</span>
            </button>
            <a class="btn message__action-btn message__boost-btn" href="#">
              <img
                src="/images/boost.svg"
                class="colorize--black"
                width="20"
                height="20"
                aria-hidden="true"
              />
              <span class="for-screen-reader">New boost</span>
            </a>
          </div>

          <div class="flex flex-wrap border-top margin-block-start-half pad-block-start-half message__actions-grid">
            <button class="btn message__action-btn center full-width" title="Reply" aria-label="Reply">
              <img
                src="/images/reply.svg"
                class="colorize--black"
                width="20"
                height="20"
                aria-hidden="true"
              />
            </button>
            <button
              id={"copy-link-#{@message.id}"}
              class="btn message__action-btn center full-width"
              title="Copy link"
              aria-label="Copy link"
              phx-hook="Copy"
              data-copy={"http://localhost/rooms/1/@#{@message.id}"}
            >
              <img
                src="/images/link.svg"
                class="colorize--black"
                width="20"
                height="20"
                aria-hidden="true"
              />
            </button>
            <a
              class="btn message__action-btn center full-width message__edit-btn"
              href="#"
              title="Edit"
              aria-label="Edit"
            >
              <img
                src="/images/pencil.svg"
                class="colorize--black"
                width="20"
                height="20"
                aria-hidden="true"
              />
            </a>
          </div>
        </div>
      </details>
    </div>
    """
  end

  attr :uploads, :map, required: true
  attr :typing, :string, default: nil

  defp demo_composer(assigns) do
    ~H"""
    <div class="composer flex align-end gap position-relative">
      <.icon_button
        icon="search"
        label="Search"
        href="#"
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
                phx-click="cancel_upload"
                phx-value-ref={entry.ref}
              >
                <span class="composer__file-thumbnail composer__file-thumbnail--common"></span>
                <span class="composer__file-caption flex align-center txt-small overflow-ellipsis">
                  {entry.client_name}
                </span>
              </button>
            </div>

            <div
              class="flex composer__input input input--actor fill-white min-width"
              style="--input-border-radius: 1.3rem"
            >
              <div class="flex align-end gap full-width">
                <img
                  src="/images/messages-outlined.svg"
                  width="22"
                  height="22"
                  class="composer__input-hint colorize--black"
                  aria-hidden="true"
                />

                <div class="flex flex-column flex-item-grow min-width gap">
                  <textarea
                    id="composer-body"
                    name="message[body]"
                    rows="1"
                    class="input"
                    aria-label="Write a message"
                    placeholder="Write a message…"
                    phx-hook="Composer"
                  ></textarea>
                </div>

                <label class="btn btn--borderless txt-small flex-item-no-shrink composer__attachment-btn input--file">
                  <img
                    src="/images/attachment.svg"
                    width="22"
                    height="22"
                    class="colorize--black"
                    aria-hidden="true"
                  />
                  <.live_file_input upload={@uploads.attachments} />
                  <span class="for-screen-reader">Attach a file</span>
                </label>

                <button type="submit" class="btn btn--reversed flex-item-no-shrink txt-small">
                  <img src="/images/arrow-up.svg" width="20" height="20" aria-hidden="true" />
                  <span class="for-screen-reader">Send Message</span>
                </button>
              </div>
            </div>
          </div>
        </fieldset>

        <div class={[
          "typing-indicator gap txt-small align-center flex-inline",
          @typing && "typing-indicator--active"
        ]}>
          <div class="typing-indicator__author spinner">{@typing}</div>
        </div>
      </form>
    </div>
    """
  end

  attr :me, :map, required: true

  defp demo_sidebar(assigns) do
    assigns =
      assign(assigns,
        directs: [{@david, true}, {@jason, false}],
        group: [@david, @jason, @bot],
        rooms: [{"All Talk", false}, {"Watercooler", false}, {"Releases", true}]
      )

    ~H"""
    <div class="sidebar__container overflow-y overflow-hide-scrollbar">
      <div class="directs gap overflow-x overflow-hide-scrollbar">
        <a href="#" class="direct direct__new">
          <span class="avatar avatar--icon">
            <img
              src="/images/messages-add.svg"
              width="20"
              height="20"
              class="colorize--black"
              aria-hidden="true"
            />
          </span>
          <span class="direct__author flex max-width min-width border-radius pad-inline-half">
            <span class="for-screen-reader">New</span>
            <span class="txt-small overflow-clip">Ping</span>
          </span>
        </a>

        <a :for={{user, unread} <- @directs} href="#" class={["direct", unread && "unread"]}>
          <span class="avatar">
            <img src={initials_avatar(user)} width="48" height="48" aria-hidden="true" />
          </span>
          <span class="direct__author flex align-center gap max-width min-width border-radius txt-small">
            <span class="txt-nowrap overflow-ellipsis">
              <span class="for-screen-reader">Ping with</span>
              {first_name(user)}
            </span>
          </span>
        </a>

        <a href="#" class="direct">
          <div class="avatar__group">
            <span :for={user <- @group} class="avatar">
              <img src={initials_avatar(user)} width="20" height="20" aria-hidden="true" />
            </span>
          </div>
          <span class="direct__author flex align-center gap max-width min-width border-radius txt-small">
            <span class="txt-nowrap overflow-ellipsis">DH+JF+DB</span>
          </span>
        </a>
      </div>

      <div class="rooms position-relative flex flex-column gap">
        <a
          :for={{name, unread} <- @rooms}
          href="#"
          style="--column-gap: 0.5em"
          class={[
            "align-center gap room btn txt-nowrap",
            unread && "unread",
            name == "Watercooler" && "room--current"
          ]}
        >
          <span class="overflow-ellipsis">{name}</span>
        </a>

        <a
          href="#"
          class="rooms__new-btn btn room align-center gap txt-reversed"
          aria-label="New Chat Room"
        >
          <img src="/images/add.svg" width="20" height="20" aria-hidden="true" />
        </a>
      </div>

      <button class="btn sidebar__toggle" phx-click={JS.toggle_class("open", to: "#sidebar")}>
        <img src="/images/menu.svg" width="20" height="20" aria-hidden="true" />
        <span class="for-screen-reader">Open menu</span>
      </button>
    </div>

    <div class="flex align-end sidebar__tools gap justify-end">
      <a href="#" class="btn avatar flex-item-no-shrink sidebar__tool">
        <img src={initials_avatar(@me)} width="48" height="48" aria-hidden="true" />
        <span class="for-screen-reader">My Settings</span>
      </a>
      <.link
        href="/dev/styleguide?view=components"
        class="btn align-center gap txt-reversed sidebar__tool"
      >
        <img src="/images/settings.svg" width="20" height="20" aria-hidden="true" />
        <span class="for-screen-reader">Account Settings</span>
      </.link>
    </div>
    """
  end

  ## Fake data

  defp fake_messages do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    yesterday = DateTime.add(now, -1, :day)
    at = fn base, minutes -> DateTime.add(base, minutes, :minute) end

    mention =
      Phoenix.HTML.raw(
        ~s|Hey <span class="mention"><a class="btn avatar" href="#">| <>
          ~s|<img src="#{initials_avatar(@me)}" width="48" height="48" aria-hidden="true"></a> | <>
          ~s|#{@me.name}</span>, can you check the deploy?|
      )

    reply =
      Phoenix.HTML.raw(
        "<blockquote>Shipping the new sidebar today</blockquote>" <>
          ~s|<cite>David Heinemeier <a href="#">#</a></cite>| <>
          "Looks great! 🚀"
      )

    [
      message(1, @david, at.(yesterday, -60), body: "Morning everyone ☕️"),
      message(2, @david, at.(yesterday, -58),
        body: "Shipping the new sidebar today",
        boosts: [{@jason, "🎉"}, {@me, "🔥"}, {@bot, "nice!"}]
      ),
      message(3, @jason, at.(yesterday, -20), html: reply),
      message(4, @me, at.(now, -45),
        body: "First message of today. Links work too: https://once.com/campfire"
      ),
      message(5, @me, at.(now, -44), body: "…and this one is threaded under it."),
      message(6, @david, at.(now, -40), emoji: true, body: "🎉🔥"),
      message(7, @bot, at.(now, -30), html: mention, mentioned: true),
      message(8, @jason, at.(now, -20), sound: {"trombone", "plays a sad trombone"}),
      message(9, @david, at.(now, -19), sound: {"yay", {:image, "yay.webp", 103, 50}}),
      message(10, @me, at.(now, -10), image: {"/images/logos/app-icon.png", 512, 512}),
      message(11, @jason, at.(now, -5), file: "quarterly-report.pdf")
    ]
  end

  defp message(id, creator, at, opts) do
    body = Keyword.get(opts, :body)

    %{
      id: id,
      creator: creator,
      at: at,
      html: Keyword.get_lazy(opts, :html, fn -> body && format_body(body) end),
      mentioned: Keyword.get(opts, :mentioned, false),
      emoji: Keyword.get(opts, :emoji, false),
      boosts: Keyword.get(opts, :boosts, []),
      sound: Keyword.get(opts, :sound),
      image: Keyword.get(opts, :image),
      file: Keyword.get(opts, :file)
    }
  end

  defp format_body(body) do
    body
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
    |> String.replace(
      ~r{https?://[^\s<]+},
      ~s|<a href="\\0" target="_blank" rel="noopener">\\0</a>|
    )
    |> String.replace("\n", "<br>")
    |> Phoenix.HTML.raw()
  end

  defp title(user), do: Enum.join(Enum.reject([user.name, user.bio], &is_nil/1), " – ")

  defp first_name(user), do: user.name |> String.split(" ") |> hd()

  # A stand-in for the /users/:id/avatar initials SVG (analysis/03-ui.md §1.19)
  defp initials_avatar(user) do
    initials = Regex.scan(~r/\b\w/u, user.name) |> Enum.join()
    color = Enum.at(@avatar_colors, rem(:erlang.crc32(to_string(user.id)), 18))

    svg = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><rect width="512" height="512" rx="50" fill="#{color}"/><text x="50%" y="50%" fill="#fff" text-anchor="middle" dominant-baseline="central" font-family="-apple-system, BlinkMacSystemFont, sans-serif" font-size="230" font-weight="800">#{initials}</text></svg>
    """

    "data:image/svg+xml;base64," <> Base.encode64(svg)
  end
end
