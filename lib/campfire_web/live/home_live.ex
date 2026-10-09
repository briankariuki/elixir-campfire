defmodule CampfireWeb.HomeLive do
  @moduledoc """
  `/`: goes to the last room you visited (if you're still a member), else your oldest room,
  else shows an empty state.
  """
  use CampfireWeb, :live_view

  alias Campfire.Chat
  alias CampfireWeb.Sidebar

  on_mount Sidebar

  @impl true
  def mount(_params, _session, socket) do
    case landing_room(socket.assigns.current_user) do
      nil ->
        {:ok, assign(socket, page_title: "Campfire", body_class: "sidebar")}

      room ->
        {:ok, push_navigate(socket, to: ~p"/rooms/#{room.id}")}
    end
  end

  defp landing_room(user) do
    with id when not is_nil(id) <- user.last_room_id,
         {:ok, room} <- Chat.get_room(id, actor: user) do
      room
    else
      _ -> Chat.oldest_room!(actor: user)
    end
  end

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
        <Sidebar.sidebar sidebar={@sidebar} current_user={@current_user} />
      </:sidebar>
    </Layouts.app>
    """
  end
end
