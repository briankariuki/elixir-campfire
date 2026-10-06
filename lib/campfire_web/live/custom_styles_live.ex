defmodule CampfireWeb.CustomStylesLive do
  @moduledoc """
  `/account/custom_styles/edit`: the admin editor for the account's custom CSS (the original's
  `accounts/custom_styles/edit`), linked from the account page.

  The CSS is stored in `Account.custom_styles` and written into `<head>` by the root layout
  (`CampfireWeb.CustomStyles`). Live navigation never re-renders the root layout, so saving does a
  full `redirect/2` back to this page: the new styles are in effect right away.
  """
  use CampfireWeb, :live_view

  import CampfireWeb.SettingsComponents, only: [back_button: 1]
  import CampfireWeb.Translations, only: [translation_button: 1]

  alias Campfire.Accounts
  alias CampfireWeb.ErrorMessages

  @impl true
  def mount(_params, _session, socket) do
    account = Accounts.get_account!()

    {:ok,
     assign(socket,
       page_title: "Custom styles",
       account: account,
       form: build_form(account, socket)
     )}
  end

  @impl true
  def handle_event("validate", %{"account" => params}, socket) do
    {:noreply, assign(socket, form: AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("save", %{"account" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: Map.take(params, ["custom_styles"])) do
      {:ok, _account} ->
        {:noreply,
         socket |> put_flash(:info, "✓") |> redirect(to: ~p"/account/custom_styles/edit")}

      {:error, form} ->
        socket = assign(socket, form: form)

        if ErrorMessages.forbidden?(form),
          do:
            {:noreply, put_flash(socket, :error, ErrorMessages.summary(%Ash.Error.Forbidden{}))},
          else: {:noreply, socket}
    end
  end

  defp build_form(account, socket) do
    account
    |> AshPhoenix.Form.for_update(:update,
      actor: socket.assigns.current_user,
      as: "account",
      warn_on_unhandled_errors?: false
    )
    |> to_form()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <:nav>
        <.back_button to={~p"/account"} />
      </:nav>

      <section class="panel panel--wide txt-align-center flex flex-column position-relative">
        <.form
          for={@form}
          id="custom-styles-form"
          phx-change="validate"
          phx-submit="save"
          class="flex flex-column gap"
        >
          <div class="panel__button">
            <.translation_button key={:custom_styles} />
          </div>

          <div class="pad-inline-double margin-inline">
            <h1 class="margin-none">Custom CSS</h1>
            <p
              class="flex flex-wrap align-center justify-center gap margin-none-block-start"
              style="--column-gap: 0.5ch; --row-gap: 0"
            >
              <span>Add custom CSS styles.</span>
              <img
                src={~p"/images/alert.svg"}
                width="16"
                height="16"
                class="flex-inline colorize--black"
                aria-hidden="true"
              />
              <span>Use Caution: you could break things.</span>
            </p>
          </div>

          <label class="flex align-start gap flex-item-grow">
            <span class="for-screen-reader">Custom CSS</span>
            <.input
              field={@form[:custom_styles]}
              type="textarea"
              class="input--code txt--small"
              placeholder="Add CSS styles…"
              autocomplete="off"
              spellcheck="false"
              autocapitalize="off"
              rows="16"
            />
          </label>

          <.icon_button
            icon="check"
            label="Save changes"
            type="submit"
            variant="reversed"
            class="center txt-large"
          />
        </.form>
      </section>
    </Layouts.app>
    """
  end
end
