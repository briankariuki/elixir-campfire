defmodule CampfireWeb.SessionController do
  @moduledoc "Sign in and sign out."
  use CampfireWeb, :controller

  alias Campfire.Accounts
  alias Campfire.Accounts.User
  alias CampfireWeb.UserAuth

  def new(conn, params) do
    render_form(conn, Map.take(params, ["email_address"]), false)
  end

  def create(conn, params) do
    email = to_string(params["email_address"])
    password = to_string(params["password"])

    case Accounts.sign_in(email, password) do
      {:ok, %User{} = user} ->
        UserAuth.log_in_user(conn, user)

      _ ->
        conn
        |> put_status(:unauthorized)
        |> put_flash(:error, "Too many requests or unauthorized.")
        |> render_form(%{"email_address" => email}, true)
    end
  end

  def delete(conn, _params) do
    UserAuth.log_out_user(conn)
  end

  # Redirects to first run until the account exists.
  defp render_form(conn, params, failed) do
    case Accounts.get_account!() do
      nil ->
        conn |> put_status(:found) |> redirect(to: ~p"/first_run")

      account ->
        conn
        |> put_view(html: CampfireWeb.AuthHTML)
        |> render(:new_session,
          page_title: "Sign in",
          account: account,
          admin: CampfireWeb.AuthHTML.contact_admin(),
          failed: failed,
          form: Phoenix.Component.to_form(params)
        )
    end
  end
end
