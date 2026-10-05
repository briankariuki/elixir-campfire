defmodule CampfireWeb.SessionTransferController do
  @moduledoc """
  Sign in on another device through a transfer link (see `CampfireWeb.Transfer`).

  GET only shows a confirm button, so link-preview bots can't use the link; PUT signs in.
  """
  use CampfireWeb, :controller

  alias Campfire.Accounts.User
  alias CampfireWeb.{Transfer, UserAuth}

  def show(conn, %{"token" => token}) do
    conn
    |> put_view(html: CampfireWeb.AuthHTML)
    |> render(:transfer, page_title: "Sign in", token: token)
  end

  def update(conn, %{"token" => token}) do
    with {:ok, user_id} <- Transfer.verify(token),
         {:ok, %User{role: role} = user} when role != :bot <-
           Campfire.Accounts.get_active_user(user_id) do
      UserAuth.log_in_user(conn, user)
    else
      _ ->
        conn
        |> put_status(:bad_request)
        |> put_view(html: CampfireWeb.ErrorHTML)
        |> render(:"400")
    end
  end
end
