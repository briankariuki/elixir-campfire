defmodule CampfireWeb.ProfileLive do
  @moduledoc """
  `/profile`: my avatar, name, email, password and bio; my rooms with involvement bells; my
  session transfer link; and the logout button.
  """
  use CampfireWeb, :live_view

  import CampfireWeb.SettingsComponents
  import CampfireWeb.Translations, only: [translation_button: 1]

  alias Campfire.{Accounts, Chat}
  alias CampfireWeb.{ErrorMessages, ImageUpload, Paths}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    {:ok,
     socket
     |> assign(page_title: user.name)
     |> assign_form(user)
     |> assign_memberships()
     |> allow_upload(:avatar,
       accept: ImageUpload.accept(),
       max_entries: 1,
       max_file_size: 10_000_000,
       auto_upload: true,
       progress: &handle_progress/3
     )}
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    {:noreply, assign(socket, form: AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("save", %{"user" => params}, socket) do
    # The avatar is only set through the upload flow
    params = Map.delete(params, "avatar_key")

    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, user} ->
        {:noreply,
         socket |> assign(current_user: user) |> assign_form(user) |> put_flash(:info, "Saved")}

      {:error, form} ->
        {:noreply, assign(socket, form: form)}
    end
  end

  def handle_event("validate_avatar", _params, socket), do: {:noreply, socket}

  def handle_event("delete_avatar", _params, socket) do
    save_avatar(socket, nil)
  end

  def handle_event("cycle_involvement", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    with %{} = membership <- Enum.find(socket.assigns.memberships, &(to_string(&1.id) == id)),
         next = next_involvement(membership.room, membership.involvement),
         {:ok, _} <- Chat.set_involvement(membership, next, actor: user) do
      {:noreply, assign_memberships(socket)}
    else
      {:error, error} -> {:noreply, put_flash(socket, :error, ErrorMessages.summary(error))}
      nil -> {:noreply, socket}
    end
  end

  defp handle_progress(:avatar, entry, socket) do
    if entry.done? do
      key =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          {:ok, ImageUpload.store(path, entry.client_name, entry.client_type)}
        end)

      if key,
        do: save_avatar(socket, key),
        else: {:noreply, put_flash(socket, :error, upload_error(:not_accepted))}
    else
      {:noreply, socket}
    end
  end

  defp save_avatar(socket, key) do
    user = socket.assigns.current_user

    case Accounts.update_profile(user, %{avatar_key: key}, actor: user) do
      {:ok, user} ->
        {:noreply, socket |> assign(current_user: user) |> assign_form(user)}

      {:error, error} ->
        Campfire.Uploads.delete(key)
        {:noreply, put_flash(socket, :error, ErrorMessages.summary(error))}
    end
  end

  defp assign_form(socket, user) do
    form =
      user
      |> AshPhoenix.Form.for_update(:update_profile, actor: user, as: "user")
      |> to_form()

    assign(socket, form: form)
  end

  defp assign_memberships(socket) do
    user = socket.assigns.current_user
    memberships = Chat.list_memberships!(actor: user, load: [room: [:users]])
    {directs, shared} = Enum.split_with(memberships, &(&1.room.kind == :direct))

    assign(socket,
      memberships: memberships,
      shared: Enum.sort_by(shared, &String.downcase(&1.room.name || "")),
      directs: Enum.sort_by(directs, & &1.room.updated_at, {:desc, DateTime})
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <:nav>
        <.back_button />
        <div class="flex-item-justify-end">
          <.icon_button icon="logout" label="Log out" href={~p"/session"} method="delete" />
        </div>
      </:nav>

      <section class="panel flex flex-column gap">
        <div class="align-center center avatar__form gap">
          <form id="avatar-form" class="txt-medium" phx-change="validate_avatar">
            <label class="btn input--file">
              <img src={~p"/images/camera.svg"} width="20" height="20" aria-hidden="true" />
              <.live_file_input upload={@uploads.avatar} class="input" />
              <span class="for-screen-reader">Upload avatar</span>
            </label>
          </form>

          <label class="btn avatar input--file txt-xx-large" for={@uploads.avatar.ref}>
            <%= case @uploads.avatar.entries do %>
              <% [entry | _] -> %>
                <.live_img_preview entry={entry} width="300" height="300" />
              <% [] -> %>
                <img
                  src={Paths.avatar_path(@current_user)}
                  width="300"
                  height="300"
                  aria-hidden="true"
                />
            <% end %>
            <span class="for-screen-reader">Avatar</span>
          </label>

          <.icon_button
            :if={@current_user.avatar_key}
            id="delete-avatar"
            icon="minus"
            label="Delete avatar"
            variant="negative"
            class="txt-small avatar__delete-btn"
            phx-click="delete_avatar"
          />
        </div>

        <p :for={err <- upload_errors(@uploads.avatar)} class="input-error txt-align-center">
          {upload_error(err)}
        </p>

        <.form for={@form} id="profile-form" phx-change="validate" phx-submit="save">
          <div class="flex flex-column gap">
            <div class="flex align-center gap">
              <.translation_button key={:user_name} />
              <.input
                field={@form[:name]}
                icon="person"
                label="Name"
                class="txt-large flex-item-grow"
                placeholder="Enter your name"
                autocomplete="name"
                required
              />
            </div>
            <div class="flex align-center gap">
              <.translation_button key={:email_address} />
              <.input
                field={@form[:email_address]}
                type="email"
                icon="email"
                label="Email address"
                class="txt-large flex-item-grow"
                placeholder="Enter your email address"
                autocomplete="username"
              />
            </div>
            <div class="flex align-center gap">
              <.translation_button key={:update_password} />
              <.input
                field={@form[:password]}
                type="password"
                icon="password"
                label="Change password"
                class="txt-large flex-item-grow"
                placeholder="Change password"
                autocomplete="new-password"
                maxlength="72"
                value=""
              />
            </div>
            <div class="flex align-start gap">
              <.translation_button key={:bio} />
              <.input
                field={@form[:bio]}
                type="textarea"
                icon="bio"
                label="Bio"
                class="txt-large flex-item-grow"
                placeholder="A few words about yourself…"
                maxlength="200"
                rows="3"
              />
            </div>

            <.icon_button
              icon="check"
              label="Save changes"
              type="submit"
              variant="reversed"
              class="center txt-large"
            />
          </div>
        </.form>

        <div class="margin-block pad-inline pad-block fill-shade border-radius">
          <menu class="flex flex-column gap margin-none pad">
            <.membership :for={m <- @shared} membership={m} current_user={@current_user} />

            <hr
              :if={@shared != [] and @directs != []}
              class="separator full-width"
              style="--border-style: solid"
            />

            <.membership :for={m <- @directs} membership={m} current_user={@current_user} />
          </menu>
        </div>

        <.transfer_link user={@current_user} current_user={@current_user} />
      </section>
    </Layouts.app>
    """
  end

  attr :membership, :map, required: true
  attr :current_user, :map, required: true

  defp membership(assigns) do
    ~H"""
    <li class="flex align-center gap margin-none min-width membership-item">
      <.link
        navigate={~p"/rooms/#{@membership.room_id}"}
        class="overflow-ellipsis fill-shade txt-primary txt-undecorated"
      >
        <strong>{room_name(@membership.room, @current_user)}</strong>
      </.link>

      <hr class="separator" aria-hidden="true" />

      <span class="txt-small">
        <.involvement_button membership={@membership} />
      </span>
    </li>
    """
  end

  defp upload_error(:too_large), do: "That file is too large"
  defp upload_error(:not_accepted), do: "Please choose an image (JPG, PNG, GIF or WebP)"
  defp upload_error(:too_many_files), do: "Choose a single image"
  defp upload_error(_), do: "The upload failed"
end
