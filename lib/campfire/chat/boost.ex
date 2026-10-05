defmodule Campfire.Chat.Boost do
  @moduledoc "A short reaction (1..16 characters, usually an emoji) on a message."

  use Ash.Resource,
    otp_app: :campfire,
    domain: Campfire.Chat,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  alias Campfire.Chat.Boost.Changes
  alias Campfire.Chat.Message

  postgres do
    table "boosts"
    repo Campfire.Repo

    references do
      reference :message, on_delete: :delete
      reference :room, on_delete: :delete
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
    end

    destroy :destroy do
      primary? true
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

  # `LoadBooster` already loads `:booster` on the created boost.
  pub_sub do
    module Campfire.PubSubBroadcaster
    prefix "room"
    broadcast_type :notification

    publish :create, [:room_id], event: "boost_created"
    publish :destroy, [:room_id], event: "boost_deleted"
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

    # Denormalized from the message (set by `SetMessage`): the topic the boost is broadcast on.
    belongs_to :room, Campfire.Chat.Room do
      allow_nil? false
      attribute_type :integer
    end

    belongs_to :booster, Campfire.Accounts.User do
      allow_nil? false
      attribute_type :integer
      public? true
    end
  end
end
