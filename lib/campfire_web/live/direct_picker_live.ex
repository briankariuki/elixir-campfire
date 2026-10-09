defmodule CampfireWeb.DirectPickerLive do
  @moduledoc """
  `/directs/new`: pick people to start a Ping with (docs/analysis/03-ui.md §1.10). The picker
  replaces the Pings strip at the top of the sidebar.

  This is not an `AshPhoenix.Form`: the only field is a search box, the chosen people live in the
  socket (they carry names and avatars for the chips) and the one submit calls the generic
  `find_or_create_direct` action through its code interface, so a form would only wrap the same
  call (the argument, policy and error handling are the action's either way).
  """
  use CampfireWeb, :live_view

  alias Campfire.{Accounts, Chat}
  alias CampfireWeb.{Paths, Sidebar}

  on_mount Sidebar

  @max_results 10

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    people = Enum.reject(Accounts.list_users!(actor: user), &(&1.id == user.id))

    {:ok,
     assign(socket,
       page_title: "New Ping",
       body_class: "sidebar",
       people: people,
       selected: [],
       query: "",
       results: []
     )}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, assign(socket, query: query, results: search(socket, query))}
  end

  def handle_event("select", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.people, &(to_string(&1.id) == id)) do
      nil ->
        {:noreply, socket}

      user ->
        selected = Enum.uniq(socket.assigns.selected ++ [user])
        {:noreply, assign(socket, selected: selected, query: "", results: [])}
    end
  end

  def handle_event("unselect", %{"id" => id}, socket) do
    selected = Enum.reject(socket.assigns.selected, &(to_string(&1.id) == id))
    {:noreply, assign(socket, selected: selected, results: search(socket, socket.assigns.query))}
  end

  def handle_event("start", _params, %{assigns: %{selected: []}} = socket) do
    {:noreply, socket}
  end

  def handle_event("start", _params, socket) do
    ids = Enum.map(socket.assigns.selected, & &1.id)

    case Chat.find_or_create_direct_room(ids, actor: socket.assigns.current_user) do
      {:ok, room} -> {:noreply, push_navigate(socket, to: ~p"/rooms/#{room.id}")}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Couldn't start that Ping.")}
    end
  end

  defp search(socket, query) do
    query = query |> String.trim() |> String.downcase()
    selected_ids = Enum.map(socket.assigns.selected, & &1.id)

    if query == "" do
      []
    else
      socket.assigns.people
      |> Enum.filter(
        &(String.contains?(String.downcase(&1.name), query) and &1.id not in selected_ids)
      )
      |> Enum.take(@max_results)
    end
  end

  defp back_path(%{last_room_id: id}) when is_integer(id), do: ~p"/rooms/#{id}"
  defp back_path(_user), do: ~p"/"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div id="message-area" class="message-area">
        <div class="message-area--empty min-width center">
          <figure class="center pad">
            <img
              src={~p"/images/messages-empty.svg"}
              class="colorize--black translucent"
              aria-hidden="true"
            />
          </figure>
        </div>
      </div>

      <:sidebar>
        <Sidebar.sidebar sidebar={@sidebar} current_user={@current_user}>
          <:directs>
            <div class="directs directs--new flex flex-column gap">
              <form
                id="direct-picker"
                class="flex gap flex-item-grow"
                phx-change="search"
                phx-submit="start"
              >
                <.link navigate={back_path(@current_user)} class="btn flex-item-no-shrink">
                  <img src={~p"/images/arrow-left.svg"} aria-hidden="true" />
                  <span class="for-screen-reader">Cancel changes</span>
                </.link>

                <section class="autocomplete__container unpad input input--actor position-relative">
                  <div class="autocomplete__input input flex flex-wrap position-relative flex-item-grow">
                    <span :for={user <- @selected} class="autocomplete__pill">
                      <img
                        src={Paths.avatar_path(user)}
                        class="avatar"
                        width="20"
                        height="20"
                        aria-hidden="true"
                      />
                      {user.name}
                      <button
                        type="button"
                        class="btn btn--plain unpad"
                        phx-click="unselect"
                        phx-value-id={user.id}
                      >
                        <img
                          src={~p"/images/remove-circle.svg"}
                          width="14"
                          height="14"
                          class="colorize--black"
                          aria-hidden="true"
                        />
                        <span class="for-screen-reader">Remove {user.name}</span>
                      </button>
                    </span>

                    <input
                      type="text"
                      name="query"
                      value={@query}
                      class="autocomplete__input input flex flex-wrap position-relative"
                      autocomplete="off"
                      phx-debounce="200"
                      phx-mounted={JS.focus()}
                      aria-label="Type names to ping someone"
                    />
                  </div>

                  <ul
                    :if={@results != []}
                    class="autocomplete__list unpad margin-none"
                    style="inset-inline: 0; inset-block-start: 100%; max-inline-size: none"
                  >
                    <li :for={user <- @results} class="autocomplete__item">
                      <button
                        type="button"
                        class="btn autocomplete__btn full-width justify-start txt-nowrap"
                        phx-click="select"
                        phx-value-id={user.id}
                      >
                        <span class="avatar">
                          <img
                            src={Paths.avatar_path(user)}
                            width="20"
                            height="20"
                            aria-hidden="true"
                          />
                        </span>
                        {user.name}
                      </button>
                    </li>
                  </ul>
                </section>

                <button
                  type="submit"
                  class="btn btn--reversed flex-item-no-shrink"
                  disabled={@selected == []}
                >
                  <img src={~p"/images/check.svg"} aria-hidden="true" />
                  <span class="for-screen-reader">Start Ping</span>
                </button>
              </form>

              <span :if={@results == []} class="txt-small translucent pad-inline-half center">
                Type names to ping someone…
              </span>
            </div>
          </:directs>
        </Sidebar.sidebar>
      </:sidebar>
    </Layouts.app>
    """
  end
end
