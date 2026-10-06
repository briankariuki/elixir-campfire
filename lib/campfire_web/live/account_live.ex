defmodule CampfireWeb.AccountLive do
  @moduledoc """
  `/account`: the account name, logo and invite link, and the list of people.

  Admins can also change the logo and name, restrict room creation to admins, regenerate the
  join code, grant or revoke the admin role, remove people, and reach the bots page. The domain
  policies enforce all of this; a forbidden action shows an error flash.
  """
  use CampfireWeb, :live_view

  import CampfireWeb.SettingsComponents

  alias Campfire.Accounts
  alias Campfire.Accounts.User
  alias CampfireWeb.{ErrorMessages, ImageUpload, Paths}

  @impl true
  def mount(_params, _session, socket) do
    admin? = User.administrator?(socket.assigns.current_user)

    socket =
      socket
      |> assign(page_title: "Account settings", admin?: admin?)
      |> assign_account(Accounts.get_account!())
      |> assign_users()

    socket =
      if admin? do
        allow_upload(socket, :logo,
          accept: ImageUpload.accept(),
          max_entries: 1,
          max_file_size: 10_000_000,
          auto_upload: true,
          progress: &handle_progress/3
        )
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_logo", _params, socket), do: {:noreply, socket}

  def handle_event("delete_logo", _params, socket) do
    update_account(socket, %{logo_key: nil})
  end

  def handle_event("validate_name", %{"account" => params} = event, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, params, target: event["_target"] || [])
    {:noreply, assign(socket, form: form)}
  end

  def handle_event("save_name", %{"account" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, account} ->
        {:noreply, socket |> assign_account(account) |> put_flash(:info, "Saved")}

      {:error, form} ->
        socket = assign(socket, form: form)

        if ErrorMessages.forbidden?(form),
          do: {:noreply, error_flash(socket, %Ash.Error.Forbidden{})},
          else: {:noreply, socket}
    end
  end

  def handle_event("toggle_restrict", _params, socket) do
    restrict = not socket.assigns.account.restrict_room_creation_to_administrators
    update_account(socket, %{restrict_room_creation_to_administrators: restrict})
  end

  def handle_event("regenerate_join_code", _params, socket) do
    case Accounts.reset_join_code(socket.assigns.account, actor: socket.assigns.current_user) do
      {:ok, account} -> {:noreply, assign_account(socket, account)}
      {:error, error} -> {:noreply, error_flash(socket, error)}
    end
  end

  def handle_event("toggle_role", %{"id" => id}, socket) do
    with_user(socket, id, fn user, opts ->
      Accounts.change_role(
        user,
        if(user.role == :administrator, do: :member, else: :administrator),
        opts
      )
    end)
  end

  def handle_event("remove_user", %{"id" => id}, socket) do
    with_user(socket, id, &Accounts.deactivate_user/2)
  end

  defp with_user(socket, id, fun) do
    me = socket.assigns.current_user

    with %User{} = user <- Enum.find(socket.assigns.all_users, &(to_string(&1.id) == id)),
         {:ok, _user} <- fun.(user, actor: me) do
      {:noreply, assign_users(socket)}
    else
      nil -> {:noreply, socket}
      {:error, error} -> {:noreply, error_flash(socket, error)}
    end
  end

  defp handle_progress(:logo, entry, socket) do
    if entry.done? do
      key =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          {:ok, ImageUpload.store(path, entry.client_name, entry.client_type)}
        end)

      if key,
        do: update_account(socket, %{logo_key: key}),
        else:
          {:noreply, put_flash(socket, :error, "Please choose an image (JPG, PNG, GIF or WebP)")}
    else
      {:noreply, socket}
    end
  end

  # The logo and the restrict switch save on their own (an upload callback and a click), so they
  # call the code interface instead of the name form.
  defp update_account(socket, attrs) do
    case Accounts.update_account(socket.assigns.account, attrs,
           actor: socket.assigns.current_user
         ) do
      {:ok, account} ->
        {:noreply, assign_account(socket, account)}

      {:error, error} ->
        Campfire.Uploads.delete(attrs[:logo_key])
        {:noreply, error_flash(socket, error)}
    end
  end

  defp error_flash(socket, error), do: put_flash(socket, :error, ErrorMessages.summary(error))

  defp assign_account(socket, account) do
    form =
      account
      |> AshPhoenix.Form.for_update(:update,
        actor: socket.assigns.current_user,
        as: "account",
        warn_on_unhandled_errors?: false
      )
      |> to_form()

    assign(socket,
      account: account,
      form: form,
      invite_url: url(~p"/join/#{account.join_code}")
    )
  end

  defp assign_users(socket) do
    users =
      Accounts.list_users!(
        %{include_banned: socket.assigns.admin?, include_bots: true},
        actor: socket.assigns.current_user
      )

    {admins, members} = Enum.split_with(users, &(&1.role == :administrator))
    assign(socket, all_users: users, admins: admins, members: members)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <:nav>
        <.back_button />
        <div :if={@admin?} class="flex align-center gap flex-item-justify-end">
          <.icon_button icon="bot" label="Set up chat bots" navigate={~p"/account/bots"} />
          <.icon_button icon="settings" label="Admin data console" href={~p"/admin"} />
        </div>
      </:nav>

      <section class="panel txt-align-center flex flex-column gap">
        <%= if @admin? do %>
          <div class="align-center center avatar__form gap">
            <form id="logo-form" class="txt-medium" phx-change="validate_logo">
              <label class="btn input--file">
                <img src={~p"/images/camera.svg"} width="20" height="20" aria-hidden="true" />
                <.live_file_input upload={@uploads.logo} class="input" />
                <span class="for-screen-reader">Upload logo</span>
              </label>
            </form>

            <label class="btn avatar input--file account-logo txt-xx-large" for={@uploads.logo.ref}>
              <%= case @uploads.logo.entries do %>
                <% [entry | _] -> %>
                  <.live_img_preview entry={entry} width="48" height="48" />
                <% [] -> %>
                  <img src={Paths.logo_path(@account)} role="presentation" width="48" height="48" />
              <% end %>
              <span class="for-screen-reader">Upload logo</span>
            </label>

            <.icon_button
              :if={@account.logo_key}
              id="delete-logo"
              icon="minus"
              label="Delete logo"
              variant="negative"
              class="txt-small avatar__delete-btn"
              phx-click="delete_logo"
            />
          </div>

          <.form
            for={@form}
            id="account-name-form"
            phx-change="validate_name"
            phx-submit="save_name"
            class="flex flex-column gap"
          >
            <div class="flex align-center gap">
              <label class="flex align-center gap flex-item-grow">
                <span class="for-screen-reader">Account name</span>
                <.input
                  field={@form[:name]}
                  class="txt-large"
                  autocomplete="off"
                  placeholder="Name this account"
                  required
                />
              </label>

              <.icon_button icon="check" label="Save changes" type="submit" variant="reversed" />
            </div>
          </.form>

          <div class="margin-block-start pad-block pad-inline-double fill-shade border-radius">
            <div class="flex align-center gap center">
              <div class="flex-item-grow flex align-center gap txt-align-start">
                <img
                  src={~p"/images/crown.svg"}
                  width="18"
                  height="18"
                  class="colorize--black"
                  aria-hidden="true"
                /> Must be admin to create new rooms
              </div>

              <.switch
                id="restrict-room-creation"
                checked={@account.restrict_room_creation_to_administrators}
                label="Must be admin to create new rooms"
                hidden_input={false}
                phx-click="toggle_restrict"
              />
            </div>
          </div>
        <% else %>
          <figure class="account-logo avatar txt-xx-large center">
            <img src={Paths.logo_path(@account)} alt="Account logo" width="300" height="300" />
          </figure>
          <h1 class="flex-item-grow txt-x-large">{@account.name}</h1>
        <% end %>

        <div class="margin-block pad-inline pad-block-start fill-shade border-radius">
          <.invite url={@invite_url} admin={@admin?} />

          <hr class="margin-block separator full-width" style="--border-style: solid" />

          <menu id="account-users" class="flex flex-column gap margin-none pad">
            <.user_row :for={user <- @admins} user={user} me={@current_user} admin?={@admin?} />

            <hr
              :if={@admins != [] and @members != []}
              class="separator full-width"
              style="--border-style: solid"
            />

            <.user_row :for={user <- @members} user={user} me={@current_user} admin?={@admin?} />
          </menu>
        </div>
      </section>
    </Layouts.app>
    """
  end

  attr :user, :map, required: true
  attr :me, :map, required: true
  attr :admin?, :boolean, required: true

  defp user_row(assigns) do
    ~H"""
    <li
      id={"account-user-#{@user.id}"}
      class={["flex align-center gap margin-none", @user.status == :banned && "banned"]}
    >
      <figure class="avatar flex-item-no-shrink" style="--avatar-size: 3.75ch;">
        <img src={Paths.avatar_path(@user)} width="48" height="48" loading="lazy" aria-hidden="true" />
      </figure>

      <div class="min-width">
        <div class="overflow-ellipsis fill-shade">
          <.link navigate={~p"/users/#{@user.id}"} class="txt-undecorated txt-primary">
            <strong>{@user.name}</strong>
          </.link>
        </div>
      </div>

      <hr class="separator" aria-hidden="true" />

      <%= if @admin? and @user.status == :active do %>
        <label
          :if={@user.role != :bot}
          class="btn txt-small flex-item-no-shrink"
          for={"role-#{@user.id}"}
        >
          <span class="for-screen-reader">
            Role: {if @user.role == :administrator, do: "Administrator", else: "Member"}
          </span>
          <img src={~p"/images/crown.svg"} width="20" height="20" aria-hidden="true" />
          <input
            type="checkbox"
            id={"role-#{@user.id}"}
            checked={@user.role == :administrator}
            disabled={@user.id == @me.id}
            phx-click="toggle_role"
            phx-value-id={@user.id}
            hidden
          />
        </label>

        <.icon_button
          :if={@user.id != @me.id}
          id={"remove-user-#{@user.id}"}
          icon="minus"
          label={"Delete #{@user.name}"}
          variant="negative"
          class="txt-small flex-item-no-shrink"
          phx-click="remove_user"
          phx-value-id={@user.id}
          data-confirm="Are you sure you want to permanently remove this person from the account? This can’t be undone."
        />
      <% end %>

      <.icon_button
        :if={@user.id == @me.id}
        icon="pencil"
        label="My settings"
        class="txt-small flex-item-no-shrink"
        navigate={~p"/profile"}
      />
    </li>
    """
  end
end
