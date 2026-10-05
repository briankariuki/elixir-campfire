defmodule CampfireWeb.AvatarController do
  @moduledoc """
  `GET /users/:id/avatar`: the uploaded avatar; for bots without one, the default bot avatar;
  otherwise an SVG with the user's initials on one of 18 colors (`crc32(id) % 18`).
  """
  use CampfireWeb, :controller

  alias Campfire.Accounts.User
  alias Campfire.Uploads

  @colors ~w(#AF2E1B #CC6324 #3B4B59 #BFA07A #ED8008 #ED3F1C #BF1B1B #736B1E #D07B53
             #736356 #AD1D1D #BF7C2A #C09C6F #698F9C #7C956B #5D618F #3B3633 #67695E)

  @cache_control "public, max-age=1800, stale-while-revalidate=604800"

  def show(conn, %{"id" => id}) do
    case Ash.get(User, id, authorize?: false) do
      {:ok, user} -> send_avatar(conn, user)
      _ -> send_resp(conn, :not_found, "Not found")
    end
  end

  defp send_avatar(conn, user) do
    cond do
      Uploads.exists?(user.avatar_key) ->
        conn
        |> put_resp_header("cache-control", @cache_control)
        |> put_resp_content_type(MIME.from_path(user.avatar_key), nil)
        |> send_file(200, Uploads.path(user.avatar_key))

      User.bot?(user) ->
        redirect(conn, to: ~p"/images/default-bot-avatar.svg")

      true ->
        conn
        |> put_resp_header("cache-control", @cache_control)
        |> put_resp_content_type("image/svg+xml")
        |> send_resp(200, initials_svg(user))
    end
  end

  @doc "The background color of a user's generated avatar."
  def color(%{id: id}), do: Enum.at(@colors, rem(:erlang.crc32(to_string(id)), 18))

  defp initials_svg(user) do
    initials = User.initials(user)

    text_length =
      if String.length(initials) >= 3,
        do: ~s( textLength="85%" lengthAdjust="spacingAndGlyphs"),
        else: ""

    """
    <svg version="1.1" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" class="avatar" aria-hidden="true">
      <g>
        <rect width="100%" height="100%" rx="50" fill="#{color(user)}" />
        <text x="50%" y="50%" fill="#FFFFFF" text-anchor="middle" dy="0.35em"#{text_length}
          font-family="-apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Helvetica, Arial, sans-serif"
          font-size="230" font-weight="800" letter-spacing="-5">#{escape(initials)}</text>
      </g>
    </svg>
    """
  end

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
