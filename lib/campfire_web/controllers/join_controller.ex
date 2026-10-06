defmodule CampfireWeb.JoinController do
  @moduledoc "Sign up through the invite link `/join/:join_code`."
  use CampfireWeb, :controller

  alias Campfire.Accounts
  alias CampfireWeb.{ErrorMessages, ImageUpload, UserAuth}

  plug :require_valid_join_code

  def new(conn, _params) do
    render_form(conn, %{})
  end

  def create(conn, %{"user" => user_params}) do
    attrs = %{
      name: user_params["name"],
      email_address: user_params["email_address"],
      password: user_params["password"],
      avatar_key: ImageUpload.store(user_params["avatar"])
    }

    case Accounts.register_user(attrs) do
      {:ok, user} ->
        UserAuth.log_in_user(conn, user)

      {:error, error} ->
        Campfire.Uploads.delete(attrs.avatar_key)

        if taken_email?(error) do
          redirect(conn, to: ~p"/session/new?#{[email_address: attrs.email_address]}")
        else
          conn
          |> put_status(:unprocessable_entity)
          |> put_flash(:error, ErrorMessages.summary(error))
          |> render_form(Map.drop(user_params, ["avatar", "password"]))
        end
    end
  end

  def create(conn, _params), do: render_form(conn, %{})

  defp render_form(conn, params) do
    conn
    |> put_view(html: CampfireWeb.AuthHTML)
    |> render(:join,
      page_title: "Sign up",
      body_class: "signup",
      account: Campfire.AccountCache.get(),
      admin: CampfireWeb.AuthHTML.contact_admin(),
      join_code: conn.params["join_code"],
      form: Phoenix.Component.to_form(params, as: :user)
    )
  end

  defp taken_email?(error) do
    ErrorMessages.field_error?(error, :email_address) and
      ErrorMessages.summary(error) =~ "taken"
  end

  defp require_valid_join_code(conn, _opts) do
    if Accounts.valid_join_code?(conn.params["join_code"]) do
      conn
    else
      conn
      |> put_status(:not_found)
      |> put_view(html: CampfireWeb.ErrorHTML)
      |> render(:"404")
      |> halt()
    end
  end
end
