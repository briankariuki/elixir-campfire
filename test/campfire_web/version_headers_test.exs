defmodule CampfireWeb.VersionHeadersTest do
  # Not async: the tests change the app env that the plug reads on every request.
  use CampfireWeb.ConnCase, async: false

  import Campfire.Fixtures

  alias CampfireWeb.VersionHeaders

  setup do
    previous = Map.new([:app_version, :git_revision], &{&1, Application.get_env(:campfire, &1)})

    on_exit(fn ->
      for {key, value} <- previous, do: Application.put_env(:campfire, key, value)
    end)
  end

  test "X-Version defaults to 0 and X-Rev is omitted", %{conn: conn} do
    Application.put_env(:campfire, :app_version, nil)
    Application.put_env(:campfire, :git_revision, nil)

    conn = get(conn, ~p"/up")
    assert get_resp_header(conn, "x-version") == ["0"]
    assert get_resp_header(conn, "x-rev") == []
  end

  test "X-Version is APP_VERSION, falling back to GIT_REVISION", %{conn: conn} do
    Application.put_env(:campfire, :app_version, "v1.2.3")
    Application.put_env(:campfire, :git_revision, "abc123")
    conn = get(conn, ~p"/up")
    assert get_resp_header(conn, "x-version") == ["v1.2.3"]
    assert get_resp_header(conn, "x-rev") == ["abc123"]

    Application.put_env(:campfire, :app_version, "")
    assert VersionHeaders.app_version() == "abc123"
  end

  test "is sent on every kind of response", %{conn: conn} do
    Application.put_env(:campfire, :app_version, "9")
    account_fixture()

    for path <- [~p"/up", ~p"/session/new", "/images/campfire-icon.png", "/nope-not-found"] do
      conn = get(conn, path)
      assert get_resp_header(conn, "x-version") == ["9"], path
    end
  end
end
