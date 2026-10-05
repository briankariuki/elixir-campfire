defmodule CampfireWeb.SearchLive do
  @moduledoc """
  `/searches?q=`: searches the messages in your rooms (docs/analysis/03-ui.md §1.16). As in the
  original, the sidebar is replaced by your recent searches.
  """
  use CampfireWeb, :live_view

  alias Campfire.Chat
  alias CampfireWeb.{MessageComponents, Sidebar}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Search",
       body_class: "sidebar searches",
       recent: load_recent(socket)
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    query = params |> Map.get("q", "") |> String.trim()
    user = socket.assigns.current_user
    messages = if query == "", do: [], else: Chat.search_messages!(query, actor: user)

    {:noreply,
     socket
     |> assign(query: query, count: length(messages))
     |> stream(:messages, messages, reset: true)}
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    query = String.trim(query)

    if query == "" do
      {:noreply, push_patch(socket, to: ~p"/searches")}
    else
      Chat.record_search(query, actor: socket.assigns.current_user)

      {:noreply,
       socket
       |> assign(recent: load_recent(socket))
       |> push_patch(to: ~p"/searches?#{[q: query]}")}
    end
  end

  def handle_event("clear_searches", _params, socket) do
    Chat.clear_searches(actor: socket.assigns.current_user)
    {:noreply, assign(socket, recent: [])}
  end

  def handle_event("play_sound", %{"url" => url}, socket) do
    {:noreply, push_event(socket, "play_sound", %{url: url})}
  end

  defp load_recent(socket), do: Chat.recent_searches!(actor: socket.assigns.current_user)

  defp return_path(%{last_room_id: id}) when is_integer(id), do: ~p"/rooms/#{id}"
  defp return_path(_user), do: ~p"/"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <:nav>
        <div :if={@query != ""} class="searches__query flex align-center gap pad-block-start-half">
          <div class="btn btn--reversed btn--faux align-center gap txt-nowrap">
            <span class="overflow-ellipsis">“{@query}”</span>
            <span class="flex-item-no-shrink">{@count}</span>
          </div>
        </div>

        <div class="searches__recents align-center gap pad-block-half overflow-y overflow-hide-scrollbar">
          <.recent_searches recent={@recent} />
        </div>
      </:nav>

      <div id="message-area" class="message-area" phx-hook="Lightbox">
        <div class="message-area--empty min-width center">
          <figure class="center pad">
            <img
              src={~p"/images/search.svg"}
              class="colorize--black translucent"
              aria-hidden="true"
            />
          </figure>
        </div>

        <div
          id="search-results"
          class="messages searches__results"
          phx-update="stream"
          phx-hook="MessageList"
        >
          <MessageComponents.message
            :for={{dom_id, message} <- @streams.messages}
            id={dom_id}
            message={message}
            current_user={@current_user}
            mode={:search}
          />
        </div>
      </div>

      <:footer>
        <div class="composer flex align-end gap">
          <.link
            navigate={return_path(@current_user)}
            class="btn flex-item-no-shrink margin-block-end"
            style="--btn-border-radius: 0.5em"
          >
            <img src={~p"/images/arrow-left.svg"} aria-hidden="true" />
            <span class="for-screen-reader">Exit search</span>
          </.link>

          <form
            id="search-form"
            class="margin-block flex-item-grow contain flex align-center gap"
            phx-submit="search"
          >
            <div class="composer__input flex align-center flex-item-grow gap full-width input input--actor min-width">
              <img
                src={~p"/images/search.svg"}
                width="20"
                height="20"
                class="composer__input-hint colorize--black"
                aria-hidden="true"
              />
              <input
                type="text"
                name="q"
                value={@query}
                class="searches__input input flex-item-grow"
                role="searchbox"
                aria-label="search"
                autocomplete="off"
                autofocus
                required
              />
              <.link patch={~p"/searches"} role="button" class="searches__reset">
                <img
                  src={~p"/images/remove.svg"}
                  width="14"
                  height="14"
                  class="colorize--black"
                  aria-hidden="true"
                />
                <span class="for-screen-reader">Clear search field</span>
              </.link>
              <button
                type="submit"
                class="btn btn--reversed flex-item-no-shrink txt-small"
                style="--btn-border-radius: 0.5em"
              >
                <img src={~p"/images/arrow-up.svg"} aria-hidden="true" />
                <span class="for-screen-reader">Search</span>
              </button>
            </div>
          </form>
        </div>
      </:footer>

      <:sidebar>
        <div class="sidebar__container overflow-y overflow-hide-scrollbar">
          <div class="rooms position-relative flex flex-column gap overflow-y overflow-hide-scrollbar">
            <.recent_searches recent={@recent} />
          </div>
        </div>
        <Sidebar.tools current_user={@current_user} />
      </:sidebar>
    </Layouts.app>
    """
  end

  attr :recent, :list, required: true

  defp recent_searches(assigns) do
    ~H"""
    <.link
      :for={search <- @recent}
      patch={~p"/searches?#{[q: search.query]}"}
      class="align-center gap room btn txt-nowrap"
    >
      <span class="overflow-ellipsis">“{search.query}”</span>
    </.link>

    <button
      :if={@recent != []}
      type="button"
      class="btn searches__btn"
      phx-click="clear_searches"
      data-confirm="Are you sure you want to clear your recent searches?"
    >
      <img src={~p"/images/broom.svg"} aria-hidden="true" />
      <span class="for-screen-reader">Clear recent searches</span>
    </button>
    """
  end
end
