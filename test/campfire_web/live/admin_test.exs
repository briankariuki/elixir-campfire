defmodule CampfireWeb.AdminTest do
  use CampfireWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Campfire.Fixtures

  setup do
    account_fixture()
    :ok
  end

  describe "/admin (AshAdmin)" do
    test "anonymous visitors are sent to sign in", %{conn: conn} do
      assert conn |> get(~p"/admin") |> redirected_to() == ~p"/session/new"
    end

    test "members are redirected away with a flash", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> get(~p"/admin")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "administrator"
    end

    test "members cannot reach nested admin pages either", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> get("/admin/accounts/user")
      assert redirected_to(conn) == ~p"/"
    end

    test "administrators get the admin UI acting as themselves", %{conn: conn} do
      admin = admin_fixture(name: "Ada Admin")
      conn = log_in_user(conn, admin)

      assert conn |> get(~p"/admin") |> html_response(200) =~ "Ash Admin"

      {:ok, view, html} = live(conn, ~p"/admin")
      assert html =~ "Accounts"
      assert html =~ "Chat"
      assert has_element?(view, "#sidebar")

      assert %{actor: %{id: id}, authorizing: true} = :sys.get_state(view.pid).socket.assigns
      assert id == admin.id
    end
  end
end
