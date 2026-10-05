defmodule Campfire.Fixtures do
  @moduledoc "Test data helpers. Internal setup uses `authorize?: false`."

  alias Campfire.{Accounts, Chat}
  alias Campfire.Accounts.{Account, User}

  def unique_email, do: "user#{System.unique_integer([:positive])}@example.com"

  def account_fixture(attrs \\ %{}) do
    account =
      Accounts.get_account!(authorize?: false) ||
        Account
        |> Ash.Changeset.for_create(:create, %{})
        |> Ash.create!(authorize?: false)

    if attrs == %{} do
      account
    else
      account
      |> Ash.Changeset.for_update(:update, attrs)
      |> Ash.update!(authorize?: false)
    end
  end

  def user_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    {role, attrs} = Map.pop(attrs, :role, :member)

    attrs =
      Map.merge(
        %{
          name: "User #{System.unique_integer([:positive])}",
          email_address: unique_email(),
          password: "secret123"
        },
        attrs
      )

    action = if role == :administrator, do: :register_administrator, else: :register

    User
    |> Ash.Changeset.for_create(action, attrs)
    |> Ash.create!(authorize?: false)
  end

  def admin_fixture(attrs \\ %{}),
    do: user_fixture(Map.put(Map.new(attrs), :role, :administrator))

  def bot_fixture(attrs \\ %{}) do
    attrs = Map.merge(%{name: "Bot #{System.unique_integer([:positive])}"}, Map.new(attrs))

    User
    |> Ash.Changeset.for_create(:create_bot, attrs)
    |> Ash.create!(authorize?: false)
  end

  def open_room_fixture(creator, name \\ nil) do
    Chat.create_open_room!(name || "Room #{System.unique_integer([:positive])}",
      actor: creator,
      authorize?: false
    )
  end

  def closed_room_fixture(creator, users, name \\ nil) do
    Chat.create_closed_room!(
      name || "Closed #{System.unique_integer([:positive])}",
      Enum.map(users, & &1.id),
      actor: creator,
      authorize?: false
    )
  end

  def direct_room_fixture(actor, others) do
    Chat.find_or_create_direct_room!(Enum.map(others, & &1.id), actor: actor)
  end

  def message_fixture(room, creator, attrs \\ %{}) do
    attrs = Map.merge(%{body: "Hello #{System.unique_integer([:positive])}"}, Map.new(attrs))
    Chat.create_message!(room, attrs, actor: creator)
  end

  def session_fixture(user, attrs \\ %{}) do
    Accounts.create_session!(
      Map.merge(%{ip_address: "8.8.8.8", user_agent: "test"}, Map.new(attrs)),
      actor: user
    )
  end

  def reload(record), do: Ash.reload!(record, authorize?: false)
end
