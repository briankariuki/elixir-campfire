defmodule Campfire.AccountCache do
  @moduledoc """
  An in-memory copy of the single `Campfire.Accounts.Account` row, for the hot read paths: the
  `CampfireWeb.CustomStyles` plug (every browser request), room mounts, the logo, the auth pages
  and the room-creation policy check.

  ## Design

  A GenServer owns a protected ETS table (`read_concurrency: true`). `get/1` reads the table in
  the calling process; only a miss goes to the database (`Campfire.Accounts.get_account!/0`) and
  hands the result to the owner to store. `nil` (first run hasn't happened) is cached too.

  ETS rather than `:persistent_term`: persistent terms are the fastest to read, but every update
  or erase triggers a global garbage collection scan of all processes, and a changed account
  would pay that on every node. The account does change rarely, but ETS reads are cheap enough
  (a copy of one small struct) and updates are free.

  It lives in the domain layer (not `CampfireWeb`) because the domain itself reads the account:
  `Campfire.Checks.CanCreateRooms` and `Account.Actions.ValidJoinCode`.

  ## Invalidation

  `Campfire.Notifiers.AccountChanged` (a notifier of `Account`) broadcasts `:account_changed` on
  the `"account"` PubSub topic after every committed create, update (name, logo, custom styles,
  restriction flag) and `reset_join_code`, including the create inside `first_run`. Every node's
  cache subscribes and clears itself, so a cluster stays consistent. A load that raced with a
  change is discarded (a version counter is checked before a loaded value is stored). As a
  safety net for changes that bypass the notifier (a missed broadcast, a release task in another
  VM) entries expire after 10 minutes.

  The window between the commit and the cache process handling the broadcast is a few
  microseconds on the same node; the admin pages (`AccountLive`, `CustomStylesLive`) read the
  database directly and so never see stale data.

  ## Configuration

  `config :campfire, Campfire.AccountCache, enabled: false` makes the child `:ignore` itself; `start_link/1` takes `enabled:` and `name:` too (the tests start their own instance); with
  no table, `get/1` reads the database every time. The test environment does this, because the
  SQL sandbox rolls the account back between tests while a cache would not.
  """

  use GenServer

  @pubsub Campfire.PubSub
  @topic "account"
  @ttl :timer.minutes(10)

  @doc "The PubSub topic the cache subscribes to."
  def topic, do: @topic

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, Keyword.put(opts, :name, name), name: name)
  end

  @doc """
  The account (or `nil` before first run). The cache is read first; on a miss (or when the cache
  isn't running) the database is read.
  """
  def get(server \\ __MODULE__) do
    with true <- :ets.whereis(server) != :undefined,
         [{:account, account, expires_at}] <- :ets.lookup(server, :account),
         true <- System.monotonic_time(:millisecond) < expires_at do
      account
    else
      _ -> load(server)
    end
  end

  @doc "Drops the cached account now (the next `get/1` reads the database)."
  def invalidate(server \\ __MODULE__) do
    if :ets.whereis(server) != :undefined, do: GenServer.call(server, :invalidate), else: :ok
  end

  defp load(server) do
    running? = :ets.whereis(server) != :undefined
    version = if running?, do: version(server)
    account = Campfire.Accounts.get_account!()
    if running?, do: store(server, version, account)
    account
  end

  defp version(server) do
    case :ets.lookup(server, :version) do
      [{:version, version}] -> version
      [] -> 0
    end
  end

  defp store(server, version, account) do
    GenServer.call(server, {:put, version, account})
  catch
    :exit, _ -> :ok
  end

  @impl GenServer
  def init(opts) do
    config = Application.get_env(:campfire, __MODULE__, [])

    if Keyword.get(opts, :enabled, Keyword.get(config, :enabled, true)) do
      name = Keyword.fetch!(opts, :name)
      :ets.new(name, [:named_table, :protected, read_concurrency: true])
      :ets.insert(name, {:version, 0})
      :ok = Phoenix.PubSub.subscribe(@pubsub, @topic)
      {:ok, name}
    else
      :ignore
    end
  end

  @impl GenServer
  def handle_call({:put, version, account}, _from, table) do
    # Only store what was loaded after the latest invalidation.
    if version(table) == version do
      expires_at = System.monotonic_time(:millisecond) + @ttl
      :ets.insert(table, {:account, account, expires_at})
    end

    {:reply, :ok, table}
  end

  def handle_call(:invalidate, _from, table) do
    clear(table)
    {:reply, :ok, table}
  end

  @impl GenServer
  def handle_info(:account_changed, table) do
    clear(table)
    {:noreply, table}
  end

  def handle_info(_message, table), do: {:noreply, table}

  defp clear(table) do
    :ets.insert(table, {:version, version(table) + 1})
    :ets.delete(table, :account)
  end
end
