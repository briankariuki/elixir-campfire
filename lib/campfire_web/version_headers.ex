defmodule CampfireWeb.VersionHeaders do
  @moduledoc """
  Adds `X-Version` (and `X-Rev` when known) to every response (the original's `VersionHeaders`
  concern), so a client can tell when the server was deployed with a new version and reload.

  The values come from `config :campfire, :app_version` / `:git_revision` (set from the
  `APP_VERSION` and `GIT_REVISION` environment variables in `config/runtime.exs`) and are read
  on each request. `X-Version` is the app version, else the git revision, else `"0"`.
  """
  @behaviour Plug

  import Plug.Conn, only: [put_resp_header: 3]

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    conn
    |> put_resp_header("x-version", app_version())
    |> put_revision()
  end

  @doc "The version sent as `X-Version`."
  def app_version do
    present(Application.get_env(:campfire, :app_version)) ||
      present(Application.get_env(:campfire, :git_revision)) || "0"
  end

  defp put_revision(conn) do
    case present(Application.get_env(:campfire, :git_revision)) do
      nil -> conn
      revision -> put_resp_header(conn, "x-rev", revision)
    end
  end

  defp present(value) when is_binary(value) and value != "", do: value
  defp present(_value), do: nil
end
