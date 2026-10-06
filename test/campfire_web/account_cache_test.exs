defmodule CampfireWeb.AccountCacheTest do
  # Not async: the cache listens to the global "account" topic, so account changes made by
  # concurrently running tests would clear it in the middle of a query count.
  use Campfire.DataCase, async: false

  import Campfire.Fixtures

  alias Campfire.{AccountCache, Accounts}

  @cache :account_cache_under_test
  @query_event [:campfire, :repo, :query]

  setup do
    # The default instance is disabled in the test environment; this one is private.
    start_supervised!({AccountCache, name: @cache, enabled: true})
    :ok
  end

  # Runs `fun` and returns {result, number of repo queries it made in this process}.
  defp count_queries(fun) do
    test_pid = self()
    ref = make_ref()
    handler_id = {__MODULE__, ref}

    :telemetry.attach(
      handler_id,
      @query_event,
      fn _event, _measurements, _metadata, _config ->
        if self() == test_pid, do: send(test_pid, {:query, ref})
      end,
      nil
    )

    try do
      result = fun.()
      {result, drain_queries(ref, 0)}
    after
      :telemetry.detach(handler_id)
    end
  end

  defp drain_queries(ref, count) do
    receive do
      {:query, ^ref} -> drain_queries(ref, count + 1)
    after
      0 -> count
    end
  end

  # The cache clears itself when it handles the broadcast; wait until it has.
  defp sync, do: _ = :sys.get_state(@cache)

  defp get, do: AccountCache.get(@cache)

  describe "get/1" do
    test "reads the database once, then serves the account from memory" do
      account = account_fixture()

      {first, queries} = count_queries(&get/0)
      assert first.id == account.id
      assert queries > 0

      {second, queries} = count_queries(&get/0)
      assert second == first
      assert queries == 0

      {_, queries} = count_queries(fn -> for _ <- 1..20, do: get() end)
      assert queries == 0
    end

    test "works before first run (no account) and picks up the account after it" do
      {nil, queries} = count_queries(&get/0)
      assert queries > 0
      {nil, 0} = count_queries(&get/0)

      assert {:ok, %{account: account}} =
               Accounts.first_run(%{
                 name: "Jason",
                 email_address: "j@example.com",
                 password: "pw"
               })

      sync()
      assert get().id == account.id
      {_, queries} = count_queries(&get/0)
      assert queries == 0
    end

    test "reads the database when the cache isn't running" do
      account = account_fixture()
      assert AccountCache.get(:no_such_account_cache).id == account.id
      assert :ok = AccountCache.invalidate(:no_such_account_cache)
    end

    test "invalidate/1 forces a reload" do
      account_fixture()
      get()
      assert :ok = AccountCache.invalidate(@cache)
      {_, queries} = count_queries(&get/0)
      assert queries > 0
    end
  end

  describe "invalidation" do
    setup do
      account = account_fixture()
      admin = user_fixture(role: :administrator)
      assert get().id == account.id
      %{account: account, admin: admin}
    end

    test "update (name)", %{account: account, admin: admin} do
      Accounts.update_account!(account, %{name: "Renamed"}, actor: admin)
      sync()
      assert get().name == "Renamed"
    end

    test "update (custom_styles)", %{account: account, admin: admin} do
      assert get().custom_styles == nil
      Accounts.update_account!(account, %{custom_styles: "body { color: red }"}, actor: admin)
      sync()
      assert get().custom_styles == "body { color: red }"
    end

    test "update (logo_key)", %{account: account, admin: admin} do
      assert get().logo_key == nil
      Accounts.update_account!(account, %{logo_key: "logo-key"}, actor: admin)
      sync()
      assert get().logo_key == "logo-key"
    end

    test "update (restrict_room_creation_to_administrators)", %{account: account, admin: admin} do
      refute get().restrict_room_creation_to_administrators

      Accounts.update_account!(account, %{restrict_room_creation_to_administrators: true},
        actor: admin
      )

      sync()
      assert get().restrict_room_creation_to_administrators
    end

    test "reset_join_code", %{account: account, admin: admin} do
      old_code = get().join_code
      assert old_code == account.join_code

      reset = Accounts.reset_join_code!(account, actor: admin)
      sync()
      assert get().join_code == reset.join_code
      refute get().join_code == old_code
    end

    test "a cached entry is dropped, so the next read is a query", %{
      account: account,
      admin: admin
    } do
      Accounts.update_account!(account, %{name: "Again"}, actor: admin)
      sync()
      {_, queries} = count_queries(&get/0)
      assert queries > 0
      {_, queries} = count_queries(&get/0)
      assert queries == 0
    end
  end

  describe "the notifier" do
    test "broadcasts :account_changed on the account topic after a commit" do
      account = account_fixture()
      admin = user_fixture(role: :administrator)
      Phoenix.PubSub.subscribe(Campfire.PubSub, AccountCache.topic())

      Accounts.update_account!(account, %{name: "Notified"}, actor: admin)
      assert_receive :account_changed

      Accounts.reset_join_code!(account, actor: admin)
      assert_receive :account_changed
    end
  end
end
