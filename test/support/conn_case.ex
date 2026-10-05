defmodule CampfireWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use CampfireWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint CampfireWeb.Endpoint

      use CampfireWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import CampfireWeb.ConnCase
    end
  end

  setup tags do
    Campfire.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Setup helper that creates a member and logs them in.

      setup :register_and_log_in_user
  """
  def register_and_log_in_user(%{conn: conn}) do
    Campfire.Fixtures.account_fixture()
    user = Campfire.Fixtures.user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  @doc "Logs `user` into `conn` with a real `Campfire.Accounts.Session`."
  def log_in_user(conn, user) do
    {:ok, session} =
      Campfire.Accounts.create_session(%{ip_address: "127.0.0.1", user_agent: "test"},
        actor: user
      )

    Phoenix.ConnTest.init_test_session(conn,
      session_token: session.token,
      live_socket_id: Campfire.Broadcast.socket_id(user.id)
    )
  end
end
