defmodule CampfireWeb.Sidebar do
  @moduledoc """
  The rooms sidebar (docs/analysis/03-ui.md §1.6): an `on_mount` hook that loads it and keeps it
  up to date, plus the `sidebar/1` component that renders it.

      on_mount CampfireWeb.Sidebar

      <:sidebar>
        <CampfireWeb.Sidebar.sidebar sidebar={@sidebar} current_user={@current_user} current_room_id={@current_room_id} />
      </:sidebar>

  The hook assigns `:sidebar` and `:current_room_id` (nil unless the LiveView sets it), subscribes
  to `"user:<id>"` and handles `:sidebar_changed`, `{:room_unread, id}`, `{:room_read, id}` and
  `{:room_removed, id}` (navigating away when it's the current room). It also handles the
  `"sidebar:ping"` event of the Ping placeholders.
  """
  use CampfireWeb, :html

  import Phoenix.LiveView,
    only: [attach_hook: 4, connected?: 1, push_navigate: 2, put_flash: 3]

  alias Campfire.{Accounts, Broadcast, Chat}
  alias CampfireWeb.Paths

  @max_placeholders 20

  def on_mount(:default, _params, _session, socket) do
    user = socket.assigns.current_user
    if connected?(socket), do: Broadcast.subscribe_user(user.id)

    {:cont,
     socket
     |> assign_new(:current_room_id, fn -> nil end)
     |> assign(:sidebar, load(user))
     |> attach_hook(:sidebar, :handle_info, &handle_info/2)
     |> attach_hook(:sidebar, :handle_event, &handle_event/3)}
  end

  @doc "Loads the sidebar data for `user`."
  def load(user) do
    memberships =
      [actor: user, load: [room: [:users]]]
      |> Chat.list_memberships!()
      |> Enum.reject(&(&1.involvement == :invisible))

    {directs, shared} = Enum.split_with(memberships, &(&1.room.kind == :direct))
    rooms = Enum.map(directs ++ shared, & &1.room)

    %{
      directs: sort_directs(Enum.map(directs, & &1.room)),
      rooms: shared |> Enum.map(& &1.room) |> Enum.sort_by(&String.downcase(&1.name || "")),
      unread: for(m <- memberships, m.unread_at, into: MapSet.new(), do: m.room_id),
      placeholders: placeholders(user, rooms),
      can_create_rooms?: Chat.can_create_open_room?(user, "New room")
    }
  end

  defp sort_directs(rooms), do: Enum.sort_by(rooms, & &1.updated_at, {:desc, DateTime})

  # Active people you have no one-on-one Ping with yet
  defp placeholders(user, rooms) do
    with_dm =
      for %{kind: :direct, users: [_, _] = users} <- rooms,
          u <- users,
          into: MapSet.new(),
          do: u.id

    Accounts.list_users!(actor: user)
    |> Enum.reject(&(&1.id == user.id or MapSet.member?(with_dm, &1.id)))
    |> Enum.take(@max_placeholders)
  end

  ## Hooks

  defp handle_info(:sidebar_changed, socket) do
    {:halt, assign(socket, :sidebar, load(socket.assigns.current_user))}
  end

  defp handle_info({:room_unread, room_id}, socket) do
    if room_id == socket.assigns.current_room_id do
      {:halt, socket}
    else
      {:halt, update(socket, :sidebar, &mark_unread(&1, room_id))}
    end
  end

  defp handle_info({:room_read, room_id}, socket) do
    {:halt, update(socket, :sidebar, &%{&1 | unread: MapSet.delete(&1.unread, room_id)})}
  end

  defp handle_info({:room_removed, room_id}, socket) do
    socket = assign(socket, :sidebar, load(socket.assigns.current_user))

    if room_id == socket.assigns.current_room_id do
      {:halt,
       socket
       |> put_flash(:error, "You no longer have access to that room.")
       |> push_navigate(to: ~p"/")}
    else
      {:halt, socket}
    end
  end

  defp handle_info(_message, socket), do: {:cont, socket}

  defp handle_event("sidebar:ping", %{"user-id" => user_id}, socket) do
    user = socket.assigns.current_user

    with {id, ""} <- Integer.parse(user_id),
         {:ok, room} <- Chat.find_or_create_direct_room([id], actor: user) do
      {:halt, push_navigate(socket, to: ~p"/rooms/#{room.id}")}
    else
      _ -> {:halt, put_flash(socket, :error, "Couldn't start that Ping.")}
    end
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  # A new message bumps a Ping to the front
  defp mark_unread(sidebar, room_id) do
    directs =
      Enum.map(sidebar.directs, fn
        %{id: ^room_id} = room -> %{room | updated_at: DateTime.utc_now()}
        room -> room
      end)

    %{sidebar | unread: MapSet.put(sidebar.unread, room_id), directs: sort_directs(directs)}
  end

  ## Component

  attr :sidebar, :map, required: true
  attr :current_user, :map, required: true
  attr :current_room_id, :integer, default: nil
  slot :directs, doc: "replaces the Pings strip (used by the new Ping picker)"

  def sidebar(assigns) do
    ~H"""
    <div class="sidebar__container overflow-y overflow-hide-scrollbar">
      {render_slot(@directs)}

      <div :if={@directs == []} class="directs gap overflow-x overflow-hide-scrollbar">
        <.link navigate={~p"/directs/new"} class="direct direct__new">
          <span class="avatar avatar--icon">
            <img
              src={~p"/images/messages-add.svg"}
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
        </.link>

        <.link
          :for={room <- @sidebar.directs}
          id={"room_#{room.id}_list"}
          navigate={~p"/rooms/#{room.id}"}
          class={[
            "direct",
            MapSet.member?(@sidebar.unread, room.id) && room.id != @current_room_id && "unread"
          ]}
        >
          <.direct_avatar members={direct_members(room, @current_user)} />
          <span class="direct__author flex align-center gap max-width min-width border-radius txt-small">
            <span class="txt-nowrap overflow-ellipsis">
              <span class="for-screen-reader">Ping with</span>
              {direct_label(direct_members(room, @current_user))}
            </span>
          </span>
        </.link>

        <button
          :for={user <- @sidebar.placeholders}
          type="button"
          class="direct borderless fill-transparent unpad"
          phx-click="sidebar:ping"
          phx-value-user-id={user.id}
        >
          <span class="avatar">
            <img src={Paths.avatar_path(user)} width="48" height="48" aria-hidden="true" />
          </span>
          <span class="direct__author flex align-center gap max-width min-width border-radius txt-small">
            <span class="txt-nowrap overflow-ellipsis">
              <span class="for-screen-reader">Start a ping with</span>
              {first_name(user)}
            </span>
          </span>
        </button>
      </div>

      <div class="rooms position-relative flex flex-column gap">
        <.link
          :for={room <- @sidebar.rooms}
          id={"room_#{room.id}_list"}
          navigate={~p"/rooms/#{room.id}"}
          style="--column-gap: 0.5em"
          class={[
            "align-center gap room btn txt-nowrap",
            MapSet.member?(@sidebar.unread, room.id) && room.id != @current_room_id && "unread",
            room.id == @current_room_id && "room--current"
          ]}
        >
          <span class="overflow-ellipsis">{room.name}</span>
        </.link>

        <.link
          :if={@sidebar.can_create_rooms?}
          navigate={~p"/rooms/new/open"}
          class="rooms__new-btn btn room align-center gap txt-reversed"
          aria-label="New Chat Room"
        >
          <img src={~p"/images/add.svg"} width="20" height="20" aria-hidden="true" />
        </.link>
      </div>

      <button
        type="button"
        class="btn sidebar__toggle"
        phx-click={JS.toggle_class("open", to: "#sidebar")}
      >
        <img src={~p"/images/menu.svg"} width="20" height="20" aria-hidden="true" />
        <span class="for-screen-reader">Open menu</span>
      </button>
    </div>

    <.tools current_user={@current_user} />
    """
  end

  attr :current_user, :map, required: true

  @doc "The profile and account settings buttons at the bottom of the sidebar."
  def tools(assigns) do
    ~H"""
    <div class="flex align-end sidebar__tools gap justify-end">
      <.link navigate={~p"/profile"} class="btn avatar flex-item-no-shrink sidebar__tool">
        <img src={Paths.avatar_path(@current_user)} width="48" height="48" aria-hidden="true" />
        <span class="for-screen-reader">My Settings</span>
      </.link>
      <.link navigate={~p"/account"} class="btn align-center gap txt-reversed sidebar__tool">
        <img src={~p"/images/settings.svg"} width="20" height="20" aria-hidden="true" />
        <span class="for-screen-reader">Account Settings</span>
      </.link>
    </div>
    """
  end

  attr :members, :list, required: true

  defp direct_avatar(%{members: [_, _ | _]} = assigns) do
    ~H"""
    <div class="avatar__group">
      <span :for={member <- Enum.take(@members, 4)} class="avatar">
        <img src={Paths.avatar_path(member)} width="20" height="20" aria-hidden="true" />
      </span>
    </div>
    """
  end

  defp direct_avatar(assigns) do
    ~H"""
    <span class="avatar">
      <img src={Paths.avatar_path(hd(@members))} width="48" height="48" aria-hidden="true" />
    </span>
    """
  end

  @doc "The other members of a direct room (or just you, in a Ping with yourself)."
  def direct_members(room, current_user) do
    case Enum.reject(room.users, &(&1.id == current_user.id)) do
      [] -> [current_user]
      others -> Enum.sort_by(others, & &1.name)
    end
  end

  @doc "The name of a room as shown to `user`: other members' names for a Ping."
  def room_name(%{kind: :direct} = room, user) do
    room |> direct_members(user) |> Enum.map_join(", ", & &1.name)
  end

  def room_name(room, _user), do: room.name

  defp direct_label([member]), do: first_name(member)
  defp direct_label(members), do: Enum.map_join(members, "+", &initials/1)

  defp initials(user) do
    user.name |> String.split() |> Enum.take(3) |> Enum.map_join(&String.upcase(String.first(&1)))
  end

  defp first_name(user), do: user.name |> String.split() |> List.first()
end
