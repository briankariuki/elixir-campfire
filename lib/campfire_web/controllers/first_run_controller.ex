defmodule CampfireWeb.FirstRunController do
  @moduledoc "First run: sets up the account and its first administrator. Only until set up."
  use CampfireWeb, :controller

  alias Campfire.Accounts
  alias CampfireWeb.{ErrorMessages, ImageUpload, UserAuth}

  plug :redirect_if_set_up

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

    case Accounts.first_run(attrs) do
      {:ok, %{user: user}} ->
        UserAuth.log_in_user(conn, user)

      {:error, :already_set_up} ->
        redirect(conn, to: ~p"/")

      {:error, error} ->
        Campfire.Uploads.delete(attrs.avatar_key)

        conn
        |> put_status(:unprocessable_entity)
        |> put_flash(:error, ErrorMessages.summary(error))
        |> render_form(Map.drop(user_params, ["avatar", "password"]))
    end
  end

  def create(conn, _params), do: render_form(conn, %{})

  defp render_form(conn, params) do
    conn
    |> put_view(html: CampfireWeb.AuthHTML)
    |> render(:first_run,
      page_title: "Set up Campfire",
      body_class: "signup",
      form: Phoenix.Component.to_form(params, as: :user)
    )
  end

  defp redirect_if_set_up(conn, _opts) do
    if Accounts.set_up?() do
      conn |> redirect(to: ~p"/") |> halt()
    else
      conn
    end
  end
end
