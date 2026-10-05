defmodule Campfire.Chat.Boost do
  @moduledoc "A short reaction (1..16 characters, usually an emoji) on a message."

  use Ash.Resource,
    otp_app: :campfire,
    domain: Campfire.Chat,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  require Ash.Query

  alias Campfire.Chat.Boost.Changes
  alias Campfire.Chat.Changes.BroadcastAfterCommit
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

      change Changes.SetMessage
      change relate_actor(:booster)
      change Changes.LoadBooster
      change {BroadcastAfterCommit, topic: :room, event: :boost_created}
    end

    destroy :destroy do
      primary? true
      require_atomic? false
      change {BroadcastAfterCommit, topic: :room, event: :boost_deleted}
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
    # Internal lookup for routing broadcasts, so no policy check. It reads the message rather
    # than a `room_id` calculation on the boost because it also runs for a just-deleted boost.
    Message
    |> Ash.Query.filter(id == ^message_id)
    |> Ash.Query.select([:room_id])
    |> Ash.read_one!(authorize?: false)
    |> case do
      %{room_id: room_id} -> room_id
      nil -> nil
    end
  end
end
