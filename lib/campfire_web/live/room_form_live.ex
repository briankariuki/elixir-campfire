defmodule CampfireWeb.RoomFormLive do
  @moduledoc """
  New and edit forms for rooms (docs/analysis/03-ui.md §1.7, §1.8).

  - `:new_open` / `:new_closed`: the "Everyone" switch links between the two. A closed room lists
    every person with a switch; the creator is always included.
  - `:edit` of an open or closed room: admins and the creator can rename it, switch it between
    open and closed, change the members and delete it. Others see it read-only.
  - `:edit` of a direct room: its participants and a "Delete Ping" button.
  """
  use CampfireWeb, :live_view

  alias Campfire.{Accounts, Chat}
  alias Campfire.Accounts.User
  alias CampfireWeb.{Paths, Sidebar}

  on_mount Sidebar

  @impl true
  def mount(params, _session, socket) do
    socket = assign(socket, body_class: "sidebar", users: [])

    case socket.assigns.live_action do
      :edit -> mount_edit(socket, params["id"])
      _new -> {:ok, mount_new(socket)}
    end
  end

  defp mount_new(socket) do
    user = socket.assigns.current_user

    assign(socket,
      page_title: "New chat room",
      room: nil,
      name: "New room",
      can_administer?: true,
      users: list_users(user, MapSet.new()),
      selected: MapSet.new([user.id]),
      initially_selected: MapSet.new([user.id])
    )
  end

  defp mount_edit(socket, id) do
    user = socket.assigns.current_user

    case Chat.get_room(id, actor: user, load: [:users]) do
      {:ok, %{kind: :direct} = room} ->
        {:ok,
         assign(socket,
           page_title: "Edit settings for #{Sidebar.room_name(room, user)}",
           room: room,
           kind: :direct
         )}

      {:ok, room} ->
        members = MapSet.new(room.users, & &1.id)

        {:ok,
         assign(socket,
           page_title: "Edit settings for #{room.name}",
           room: room,
           kind: room.kind,
           name: room.name,
           can_administer?: User.can_administer?(user, room),
           users: list_users(user, members),
           selected: members,
           initially_selected: members
         )}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "That room doesn't exist or you don't have access to it.")
         |> push_navigate(to: ~p"/")}
    end
  end

  # Saving a closed room revokes everyone not submitted, so the list must include every member who
  # can hold access: bots, and banned members (they keep their memberships so an unban restores
  # their access). Banned people who aren't members aren't offered.
  defp list_users(user, member_ids) do
    %{include_bots: true, include_banned: true}
    |> Accounts.list_users!(actor: user)
    |> Enum.filter(&(&1.status != :banned or &1.id in member_ids))
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    case socket.assigns.live_action do
      :new_open -> {:noreply, assign(socket, kind: :open)}
      :new_closed -> {:noreply, assign(socket, kind: :closed)}
      :edit -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event(event, _params, %{assigns: %{kind: :direct}} = socket)
      when event in ["change", "toggle_kind", "save"],
      do: {:noreply, socket}

  def handle_event("change", params, socket) do
    socket = assign(socket, name: Map.get(params, "name", socket.assigns.name))

    # Only member switches change the selection (not the name or the Everyone switch)
    if socket.assigns.kind == :closed and
         (params["_target"] == ["user_ids"] or Map.has_key?(params, "user_ids")) do
      {:noreply, assign(socket, selected: selected_ids(params))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle_kind", _params, %{assigns: %{can_administer?: true}} = socket) do
    kind = if socket.assigns.kind == :open, do: :closed, else: :open
    {:noreply, assign(socket, kind: kind)}
  end

  def handle_event("save", params, socket) do
    socket = assign(socket, name: Map.get(params, "name", socket.assigns.name))
    ids = if socket.assigns.kind == :closed, do: selected_ids(params), else: []

    case save(socket, String.trim(socket.assigns.name), ids) do
      {:ok, room} ->
        {:noreply, push_navigate(socket, to: ~p"/rooms/#{room.id}")}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, put_flash(socket, :error, "You can't do that.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Please give the room a name.")}
    end
  end

  def handle_event("delete", _params, socket) do
    case Chat.destroy_room(socket.assigns.room, actor: socket.assigns.current_user) do
      :ok ->
        {:noreply, socket |> put_flash(:info, "Deleted") |> push_navigate(to: ~p"/")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "You can't delete this room.")}
    end
  end

  defp save(%{assigns: %{room: nil, kind: :open, current_user: user}}, name, _ids),
    do: Chat.create_open_room(name, actor: user)

  defp save(%{assigns: %{room: nil, kind: :closed, current_user: user}}, name, ids),
    do: Chat.create_closed_room(name, ids, actor: user)

  defp save(%{assigns: %{room: room, kind: :open, current_user: user}}, name, _ids),
    do: Chat.update_open_room(room, %{name: name}, actor: user)

  defp save(%{assigns: %{room: room, kind: :closed, current_user: user}}, name, ids),
    do: Chat.update_closed_room(room, %{name: name, user_ids: ids}, actor: user)

  defp selected_ids(params) do
    params
    |> Map.get("user_ids", [])
    |> Enum.flat_map(fn id ->
      case Integer.parse(id) do
        {id, ""} -> [id]
        _ -> []
      end
    end)
    |> MapSet.new()
  end

  defp back_path(%{room: %{id: id}}), do: ~p"/rooms/#{id}"
  defp back_path(%{current_user: %{last_room_id: id}}) when is_integer(id), do: ~p"/rooms/#{id}"
  defp back_path(_assigns), do: ~p"/"

  ## Render

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <:nav>
        <div class="flex-item-justify-start">
          <.icon_button icon="arrow-left" label="Go Back" navigate={back_path(assigns)} />
        </div>
      </:nav>

      <div class="overflow-y pad-block" style="flex: 1">
        <%= if @kind == :direct do %>
          <.direct_settings room={@room} current_user={@current_user} />
        <% else %>
          <.room_settings {assigns} />
        <% end %>
      </div>

      <:sidebar>
        <Sidebar.sidebar sidebar={@sidebar} current_user={@current_user} />
      </:sidebar>
    </Layouts.app>
    """
  end

  defp room_settings(assigns) do
    {selected, unselected} =
      Enum.split_with(assigns.users, &(&1.id in assigns.initially_selected))

    assigns = assign(assigns, selected_users: selected, unselected_users: unselected)

    ~H"""
    <section class="panel txt-align-center center margin-block-double">
      <form id="room-form" phx-change="change" phx-submit="save">
        <div class="flex align-center gap">
          <label :if={@can_administer?} class="flex-item-grow txt-large">
            <input
              type="text"
              name="name"
              id="room_name"
              value={@name}
              class="input full-width"
              placeholder="Name the room"
              autocomplete="off"
              required
              autofocus
            />
            <span class="for-screen-reader">Name this room</span>
          </label>
          <h1 :if={!@can_administer?} class="flex-item-grow txt-x-large">{@name}</h1>
        </div>

        <hr class="margin-block borderless" />

        <section class="room-access margin-block pad-inline fill-shade border-radius">
          <menu class="flex flex-column gap margin-none pad overflow-y constrain-height">
            <li :if={@can_administer?} class="flex align-center gap margin-none">
              <figure
                class="avatar flex-item-no-shrink"
                style="--avatar-border-radius: 0; --avatar-size: 4ch;"
              >
                <img
                  src={~p"/images/everyone.svg"}
                  class="colorize--black"
                  style="background-color: transparent"
                  aria-hidden="true"
                />
                <span class="for-screen-reader">Everyone</span>
              </figure>
              <div class="min-width">
                <div class="overflow-ellipsis fill-shade"><strong>Everyone</strong></div>
              </div>
              <hr class="separator" aria-hidden="true" />
              <.everyone_switch room={@room} kind={@kind} />
            </li>

            <hr :if={@can_administer?} class="separator full-width" style="--border-style: solid" />

            <%= if @kind == :open do %>
              <.member :for={user <- @users} user={user}>
                <img
                  :if={@can_administer?}
                  src={~p"/images/check.svg"}
                  width="20"
                  height="20"
                  class="colorize--black flex-item-no-shrink"
                  aria-hidden="true"
                />
              </.member>
            <% else %>
              <.member :for={user <- @selected_users} user={user}>
                <.member_switch
                  :if={@can_administer?}
                  user={user}
                  checked={user.id in @selected}
                  locked={is_nil(@room) and user.id == @current_user.id}
                />
              </.member>
              <hr
                :if={@selected_users != [] and @unselected_users != []}
                class="separator full-width"
                style="--border-style: solid"
              />
              <.member :for={user <- @unselected_users} user={user}>
                <.member_switch :if={@can_administer?} user={user} checked={user.id in @selected} />
              </.member>
            <% end %>
          </menu>
        </section>

        <button :if={@can_administer?} type="submit" class="btn btn--reversed txt-large center">
          <img src={~p"/images/check.svg"} width="20" height="20" aria-hidden="true" />
          <span class="for-screen-reader">Save</span>
        </button>
      </form>
    </section>

    <section :if={@room && @can_administer?} class="panel txt-align-center center margin-block">
      <button
        type="button"
        class="btn btn--negative max-width"
        aria-label={"Delete #{@room.name}"}
        phx-click="delete"
        data-confirm="Are you sure you want to delete this room and all messages in it? This can’t be undone."
      >
        <img src={~p"/images/trash.svg"} width="20" height="20" aria-hidden="true" />
        <span class="overflow-ellipsis">{@room.name}</span>
      </button>
    </section>
    """
  end

  attr :room, :any, required: true
  attr :kind, :atom, required: true

  # New rooms: a link between the open and closed forms. Existing rooms: switches the kind.
  defp everyone_switch(%{room: nil} = assigns) do
    ~H"""
    <.link
      patch={if @kind == :open, do: ~p"/rooms/new/closed", else: ~p"/rooms/new/open"}
      replace
      class="btn--faux flex-inline"
      tabindex="-1"
      id="everyone-switch"
    >
      <label class="switch">
        <input type="checkbox" class="switch__input" checked={@kind == :open} />
        <span class="switch__btn round"></span>
        <span class="for-screen-reader">
          {if @kind == :open,
            do: "Give only some access to this room",
            else: "Give everyone access to this room"}
        </span>
      </label>
    </.link>
    """
  end

  defp everyone_switch(assigns) do
    ~H"""
    <label class="switch" id="everyone-switch">
      <input
        type="checkbox"
        class="switch__input"
        checked={@kind == :open}
        phx-click="toggle_kind"
      />
      <span class="switch__btn round"></span>
      <span class="for-screen-reader">Give everyone access to this room</span>
    </label>
    """
  end

  attr :user, :map, required: true
  slot :inner_block

  defp member(assigns) do
    ~H"""
    <li class="flex align-center gap margin-none" data-value={String.downcase(@user.name)}>
      <figure class="avatar flex-item-no-shrink" style="--avatar-size: 4ch;">
        <img src={Paths.avatar_path(@user)} width="48" height="48" loading="lazy" aria-hidden="true" />
      </figure>
      <div class="min-width">
        <div class="overflow-ellipsis fill-shade"><strong>{@user.name}</strong></div>
        <div :if={@user.status == :banned} class="txt-small">Banned</div>
      </div>
      <hr class="separator" aria-hidden="true" />
      {render_slot(@inner_block)}
    </li>
    """
  end

  attr :user, :map, required: true
  attr :checked, :boolean, required: true
  attr :locked, :boolean, default: false

  defp member_switch(%{locked: true} = assigns) do
    ~H"""
    <input type="hidden" name="user_ids[]" value={@user.id} />
    <img
      src={~p"/images/check.svg"}
      width="20"
      height="20"
      class="colorize--black flex-item-no-shrink"
      aria-hidden="true"
    />
    """
  end

  defp member_switch(assigns) do
    ~H"""
    <label class="switch flex-item-no-shrink">
      <input
        type="checkbox"
        name="user_ids[]"
        value={@user.id}
        checked={@checked}
        class="switch__input"
        id={"user_#{@user.id}"}
      />
      <span class="switch__btn round"></span>
      <span class="for-screen-reader">Give {@user.name} access to this room</span>
    </label>
    """
  end

  attr :room, :map, required: true
  attr :current_user, :map, required: true

  defp direct_settings(assigns) do
    ~H"""
    <div class="panel txt-align-center center margin-block-double">
      <section class="directs--edit margin-block-end">
        <div
          :for={user <- Sidebar.direct_members(@room, @current_user)}
          class="member flex flex-column gap fill-shade pad border-radius"
        >
          <figure
            class="avatar center"
            style="--avatar-border-radius: 10ch; --avatar-size: 10ch;"
          >
            <img src={Paths.avatar_path(user)} width="48" height="48" aria-hidden="true" />
          </figure>
          <strong>{user.name}</strong>
        </div>
      </section>

      <button
        type="button"
        class="btn btn--negative center"
        aria-label="Delete Ping"
        phx-click="delete"
        data-confirm="Are you sure you want to delete this ping and all messages in it? This can’t be undone."
      >
        <img src={~p"/images/trash.svg"} width="20" height="20" aria-hidden="true" /> Ping
      </button>
    </div>
    """
  end
end
