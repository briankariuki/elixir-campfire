defmodule CampfireWeb.UserLive do
  @moduledoc """
  `/users/:id`: a person's profile card with a "Ping" button. Admins also see the email address,
  the user's session transfer link, and a Ban / Remove ban button.
  """
  use CampfireWeb, :live_view

  import CampfireWeb.SettingsComponents

  alias Campfire.{Accounts, Chat}
  alias Campfire.Accounts.User
  alias CampfireWeb.{ErrorMessages, Paths}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Accounts.get_user(id, actor: socket.assigns.current_user) do
      {:ok, user} ->
        {:ok,
         socket
         |> assign(page_title: user.name, user: user)
         |> assign(admin?: User.administrator?(socket.assigns.current_user))}

      {:error, _} ->
        {:ok, socket |> put_flash(:error, "User not found") |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("ping", _params, socket) do
    case Chat.find_or_create_direct_room([socket.assigns.user.id],
           actor: socket.assigns.current_user
         ) do
      {:ok, room} -> {:noreply, push_navigate(socket, to: ~p"/rooms/#{room.id}")}
      {:error, error} -> {:noreply, put_flash(socket, :error, ErrorMessages.summary(error))}
    end
  end

  def handle_event("ban", _params, socket) do
    update_user(socket, &Accounts.ban_user/2, "#{socket.assigns.user.name} was banned")
  end

  def handle_event("unban", _params, socket) do
    update_user(socket, &Accounts.unban_user/2, "The ban was removed")
  end

  defp update_user(socket, fun, notice) do
    case fun.(socket.assigns.user, actor: socket.assigns.current_user) do
      {:ok, user} -> {:noreply, socket |> assign(user: user) |> put_flash(:info, notice)}
      {:error, error} -> {:noreply, put_flash(socket, :error, ErrorMessages.summary(error))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <:nav>
        <.back_button />
        <div :if={@current_user.id == @user.id} class="flex align-center gap flex-item-justify-end">
          <.icon_button icon="pencil" label="Edit my profile" navigate={~p"/profile"} />
        </div>
      </:nav>

      <section class="panel txt-align-center">
        <div class={["flex flex-column gap", @user.status == :banned && "banned"]}>
          <div class="avatar txt-xx-large center" style="background: white">
            <img src={Paths.avatar_path(@user)} alt="Profile avatar" class="avatar" />
          </div>

          <%= cond do %>
            <% @user.role == :bot -> %>
              <div class="pad-double--inline push--inline push--block-start">
                <.ping_button :if={@user.status == :active} user={@user} />
                <div :if={@user.status != :active}>{@user.name} is no longer on this account</div>
              </div>
            <% @user.status == :deactivated -> %>
              <div>
                <h1 class="txt-x-large margin-none">{@user.name}</h1>
                <div>{@user.name} is no longer on this account</div>
              </div>
            <% true -> %>
              <div class="flex flex-column gap" style="--row-gap: calc(var(--block-space) / 3)">
                <h1 class="txt-x-large txt-tight-lines margin-none">{@user.name}</h1>
                <div :if={@admin?}>
                  <a href={"mailto:#{@user.email_address}"}>{@user.email_address}</a>
                </div>
                <div>{@user.bio}</div>
              </div>

              <%= if @user.status == :active do %>
                <div class="pad-inline-double margin-inline margin-block-start">
                  <.ping_button user={@user} />
                </div>

                <%= if @admin? do %>
                  <hr class="margin-block-start borderless" />
                  <.transfer_link user={@user} current_user={@current_user} />
                <% end %>
              <% end %>

              <div :if={@admin? and @current_user.id != @user.id} class="margin-block-start">
                <.button
                  :if={@user.status == :active}
                  id="ban-user"
                  class="full-width"
                  phx-click="ban"
                  data-confirm="Are you sure you want to ban this user? This will log them out, delete their messages, and block their IP addresses."
                >
                  <img src={~p"/images/cancel.svg"} aria-hidden="true" />
                  <span>Ban {@user.name}</span>
                </.button>
                <.button
                  :if={@user.status == :banned}
                  id="unban-user"
                  variant="negative"
                  class="full-width"
                  phx-click="unban"
                  data-confirm="Are you sure you want to remove the ban on this user?"
                >
                  <img src={~p"/images/cancel.svg"} aria-hidden="true" />
                  <span>Remove ban</span>
                </.button>
              </div>
          <% end %>
        </div>
      </section>
    </Layouts.app>
    """
  end

  attr :user, :map, required: true

  defp ping_button(assigns) do
    ~H"""
    <.button id="ping-user" variant="reversed" class="full-width txt-large" phx-click="ping">
      <img src={~p"/images/messages.svg"} aria-hidden="true" />
      <span class="for-screen-reader">Ping {@user.name}</span>
    </.button>
    """
  end
end
