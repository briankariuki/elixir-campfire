defmodule CampfireWeb.AccountLogoController do
  @moduledoc "`GET /account/logo` (public): the uploaded logo, or the Campfire icon."
  use CampfireWeb, :controller

  alias Campfire.{Accounts, Uploads}

  @cache_control "public, max-age=300, stale-while-revalidate=604800"

  def show(conn, _params) do
    {content_type, path} =
      case Accounts.get_account!() do
        %{logo_key: key} when is_binary(key) ->
          if Uploads.exists?(key), do: {MIME.from_path(key), Uploads.path(key)}, else: default()

        _ ->
          default()
      end

    conn
    |> put_resp_header("cache-control", @cache_control)
    |> put_resp_content_type(content_type, nil)
    |> send_file(200, path)
  end

  defp default do
    {"image/png", Application.app_dir(:campfire, "priv/static/images/campfire-icon.png")}
  end
end
