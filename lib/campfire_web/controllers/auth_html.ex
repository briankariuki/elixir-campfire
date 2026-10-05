defmodule CampfireWeb.AuthHTML do
  @moduledoc """
  Pages for signed-out visitors: first run, sign in, join (invite link) and session transfer.
  Markup follows the original `first_runs/show`, `sessions/new` and `users/new` views.
  """
  use CampfireWeb, :html

  alias CampfireWeb.Paths

  ## First run (GET /first_run)

  def first_run(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.form for={@form} action={~p"/first_run"} multipart class="center max-width">
        <.nametag form={@form} submit_icon="arrow-right">
          <:legend>
            <legend class="txt-large txt-align-center"><strong>Set up Campfire</strong></legend>
          </:legend>
        </.nametag>
      </.form>
    </Layouts.app>
    """
  end

  ## Join (GET /join/:join_code)

  def join(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <:nav>
        <div class="flex-item-justify-end">
          <.icon_button
            icon="login-keys"
            label="Sign in"
            href={~p"/session/new"}
            class="flex-item-justify-end"
          />
        </div>
      </:nav>

      <.form for={@form} action={~p"/join/#{@join_code}"} multipart class="center">
        <.nametag form={@form} submit_icon="check">
          <:legend>
            <legend class="txt-align-center flex gap">
              <.account_logo account={@account} />
              <strong class="txt-large">{@account.name}</strong>
            </legend>
          </:legend>
        </.nametag>
      </.form>

      <.help_contact admin={@admin} />
    </Layouts.app>
    """
  end

  ## Sign in (GET /session/new)

  def new_session(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="txt-align-center">
        <div class={["panel", @failed && "shake"]}>
          <.account_logo account={@account} class="center margin-block-end txt-xx-large" />

          <.form for={@form} action={~p"/session"} class="flex flex-column gap">
            <fieldset class="flex flex-column gap center-block upad">
              <legend class="txt-large txt-align-center"><strong>{@account.name}</strong></legend>

              <.input
                field={@form[:email_address]}
                type="email"
                icon="email"
                label="Email address"
                class="txt-large"
                placeholder="Enter your email address"
                autocomplete="username"
                autofocus
                required
              />
              <.input
                field={@form[:password]}
                type="password"
                icon="password"
                label="Password"
                class="txt-large"
                placeholder="Enter your password"
                autocomplete="current-password"
                maxlength="72"
                required
              />

              <.icon_button
                icon="arrow-right"
                label="Go"
                type="submit"
                variant="reversed"
                class="center txt-large"
              />
            </fieldset>
          </.form>
        </div>

        <.help_contact admin={@admin} />
      </section>
    </Layouts.app>
    """
  end

  ## Session transfer (GET /session/transfers/:token)

  def transfer(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="panel txt-align-center flex flex-column gap">
        <h1 class="txt-large margin-none">Sign in on this device</h1>
        <.form for={%{}} action={~p"/session/transfers/#{@token}"} method="put">
          <.button variant="reversed" type="submit" class="center txt-large">
            <img src={~p"/images/arrow-right.svg"} aria-hidden="true" />
            <span>Continue</span>
          </.button>
        </.form>
      </section>
    </Layouts.app>
    """
  end

  @doc "The administrator shown as the help contact on the sign-in and join pages (or nil)."
  def contact_admin do
    case Campfire.Accounts.first_administrator() do
      {:ok, admin} -> admin
      _ -> nil
    end
  end

  ## Components

  attr :form, Phoenix.HTML.Form, required: true
  attr :submit_icon, :string, required: true
  slot :legend, required: true

  defp nametag(assigns) do
    ~H"""
    <section class="nametag u-relative">
      <div class="flex justify-center align-center pad-block">
        <img src={~p"/images/lanyard.svg"} class="nametag__lanyard" aria-hidden="true" />
      </div>

      <div class="nametag__inner flex flex-column gap">
        <fieldset class="flex flex-column center-block">
          {render_slot(@legend)}

          <label class="align-center center avatar__form gap">
            <div class="btn input--file">
              <img src={~p"/images/camera.svg"} aria-hidden="true" />
              <input type="file" name={@form[:avatar].name} class="input" accept="image/*" />
              <span class="for-screen-reader">Add your avatar</span>
            </div>

            <div class="btn avatar input--file txt-xx-large">
              <img src={~p"/images/default-avatar.svg"} aria-hidden="true" alt="Add your avatar" />
              <span class="for-screen-reader">Avatar</span>
            </div>
          </label>
        </fieldset>

        <.input
          field={@form[:name]}
          icon="person"
          label="Name"
          class="txt-large"
          placeholder="Name"
          autocomplete="name"
          autofocus
          required
        />
        <.input
          field={@form[:email_address]}
          type="email"
          icon="email"
          label="Email address"
          class="txt-large"
          placeholder="Email address"
          autocomplete="username"
          required
        />
        <.input
          field={@form[:password]}
          type="password"
          icon="password"
          label="Password"
          class="txt-large"
          placeholder="Password"
          autocomplete="new-password"
          maxlength="72"
          value=""
          required
        />

        <.icon_button
          icon={@submit_icon}
          label="Save"
          type="submit"
          variant="reversed"
          class="center txt-large"
        />
      </div>
    </section>
    """
  end

  attr :account, :any, required: true
  attr :class, :string, default: nil

  def account_logo(assigns) do
    ~H"""
    <figure class={["account-logo avatar", @class]}>
      <img src={Paths.logo_path(@account)} alt="Account logo" width="300" height="300" />
    </figure>
    """
  end

  attr :admin, :any, default: nil

  defp help_contact(assigns) do
    ~H"""
    <div :if={@admin} class="txt-align-center margin-block-double full-width">
      <a
        href={"mailto:#{@admin.email_address}"}
        class="btn center"
        title={"Email #{@admin.name}"}
      >
        <img src={~p"/images/lifebuoy.svg"} aria-hidden="true" />
        <span>{@admin.email_address}</span>
      </a>
    </div>
    """
  end
end
