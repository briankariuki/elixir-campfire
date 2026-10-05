defmodule Campfire.Chat.Boost do
  @moduledoc "A short reaction (1..16 characters, usually an emoji) on a message."

  use Ash.Resource,
    otp_app: :campfire,
    domain: Campfire.Chat,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  import Ecto.Query

  alias Ash.Changeset
  alias Campfire.{Broadcast, Repo}
  alias Campfire.Chat.Message

  postgres do
    table "boosts"
    repo Campfire.Repo

    references do
      reference :message, on_delete: :delete
      reference :booster, on_delete: :delete
    end

    custom_indexes do
      index [:message_id]
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:content]
      argument :message, :struct, allow_nil?: false, constraints: [instance_of: Message]

      change fn changeset, _context ->
        case Changeset.get_argument(changeset, :message) do
          %{id: id} -> Changeset.force_change_attribute(changeset, :message_id, id)
          _ -> changeset
        end
      end

      change relate_actor(:booster)

      change after_action(fn _changeset, boost, _context ->
               {:ok, Ash.load!(boost, [:booster], authorize?: false)}
             end)

      change after_transaction(fn
               _changeset, {:ok, boost}, _context ->
                 Broadcast.room(room_id(boost), {:boost_created, boost})
                 {:ok, boost}

               _changeset, error, _context ->
                 error
             end)
    end

    destroy :destroy do
      primary? true
      require_atomic? false

      change after_transaction(fn
               _changeset, {:ok, boost}, _context ->
                 Broadcast.room(room_id(boost), {:boost_deleted, boost})
                 {:ok, boost}

               _changeset, error, _context ->
                 error
             end)
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(exists(message.room.memberships, user_id == ^actor(:id)))
    end

    policy action(:create) do
      authorize_if Campfire.Checks.RoomMember
    end

    policy action(:destroy) do
      authorize_if expr(booster_id == ^actor(:id))
    end
  end

  attributes do
    integer_primary_key :id

    attribute :content, :string do
      allow_nil? false
      constraints min_length: 1, max_length: 16
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :message, Message do
      allow_nil? false
      attribute_type :integer
      public? true
    end

    belongs_to :booster, Campfire.Accounts.User do
      allow_nil? false
      attribute_type :integer
      public? true
    end
  end

  @doc "The id of the room the boost's message is in."
  def room_id(%__MODULE__{message_id: message_id}) do
    Repo.one(from m in Message, where: m.id == ^message_id, select: m.room_id)
  end
end
