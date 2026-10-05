defmodule Campfire.Chat.Room do
  @moduledoc """
  An open, closed or direct room. See docs/DOMAIN_API.md for the actions.
  """

  use Ash.Resource,
    otp_app: :campfire,
    domain: Campfire.Chat,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Campfire.Chat.RoomChanges

  postgres do
    table "rooms"
    repo Campfire.Repo

    references do
      reference :creator, on_delete: :nothing
    end
  end

  actions do
    defaults [:read]

    read :for_user do
      description "The actor's rooms, ordered by name."
      prepare build(sort: [sort_name: :asc, id: :asc])
    end

    create :create_open do
      accept [:name]
      change set_attribute(:kind, :open)
      change relate_actor(:creator)
      change after_action(&RoomChanges.grant_active_users/3)
      change after_transaction(&RoomChanges.notify_members/3)
    end

    create :create_closed do
      accept [:name]
      argument :user_ids, {:array, :integer}, default: []
      change set_attribute(:kind, :closed)
      change relate_actor(:creator)
      change after_action(&RoomChanges.revise_members/3)
      change after_transaction(&RoomChanges.notify_members/3)
    end

    create :create_direct do
      description "Internal: use Campfire.Chat.find_or_create_direct_room/2."
      accept []
      argument :user_ids, {:array, :integer}, allow_nil?: false
      change set_attribute(:kind, :direct)
      change relate_actor(:creator)
      change &RoomChanges.set_direct_key/2
      change after_action(&RoomChanges.grant_direct_users/3)
      change after_transaction(&RoomChanges.notify_members/3)
    end

    action :find_or_create_direct, :struct do
      description "Finds the direct room for exactly these users (plus the actor), or creates it."
      constraints instance_of: __MODULE__
      argument :user_ids, {:array, :integer}, allow_nil?: false
      run &RoomChanges.find_or_create_direct/2
    end

    update :update_open do
      require_atomic? false
      accept [:name]
      validate &RoomChanges.validate_not_direct/2
      change set_attribute(:kind, :open)
      change after_action(&RoomChanges.grant_active_users/3)
      change after_transaction(&RoomChanges.notify_members/3)
    end

    update :update_closed do
      require_atomic? false
      accept [:name]
      argument :user_ids, {:array, :integer}, default: []
      validate &RoomChanges.validate_not_direct/2
      change set_attribute(:kind, :closed)
      change after_action(&RoomChanges.revise_members/3)
      change after_transaction(&RoomChanges.notify_members/3)
    end

    destroy :destroy do
      primary? true
      description "Deletes the room with its memberships, messages, boosts and attachment files."
      require_atomic? false
      change &RoomChanges.destroy_contents/2
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(exists(memberships, user_id == ^actor(:id)))
    end

    policy action([:create_open, :create_closed]) do
      authorize_if Campfire.Checks.CanCreateRooms
    end

    policy action([:create_direct, :find_or_create_direct]) do
      authorize_if Campfire.Checks.ActiveActor
    end

    policy action([:update_open, :update_closed]) do
      authorize_if actor_attribute_equals(:role, :administrator)
      authorize_if expr(creator_id == ^actor(:id))
    end

    policy action(:destroy) do
      authorize_if expr(kind == :direct and exists(memberships, user_id == ^actor(:id)))
      authorize_if expr(kind != :direct and ^actor(:role) == :administrator)
      authorize_if expr(kind != :direct and creator_id == ^actor(:id))
    end
  end

  attributes do
    integer_primary_key :id

    attribute :name, :string, public?: true

    attribute :kind, :atom do
      allow_nil? false
      constraints one_of: [:open, :closed, :direct]
      public? true
    end

    attribute :direct_key, :string, public?: true

    timestamps()
  end

  relationships do
    belongs_to :creator, Campfire.Accounts.User do
      allow_nil? false
      attribute_type :integer
      public? true
    end

    has_many :memberships, Campfire.Chat.Membership

    many_to_many :users, Campfire.Accounts.User do
      through Campfire.Chat.Membership
      source_attribute_on_join_resource :room_id
      destination_attribute_on_join_resource :user_id
    end

    has_many :messages, Campfire.Chat.Message
  end

  calculations do
    calculate :sort_name, :string, expr(string_downcase(name))
  end

  identities do
    identity :unique_direct_key, [:direct_key]
  end

  @doc "The involvement new memberships get: `:everything` for direct rooms, else `:mentions`."
  def default_involvement(%{kind: :direct}), do: :everything
  def default_involvement(_), do: :mentions

  @doc "The canonical key of a direct room: the sorted, unique member ids joined with `-`."
  def direct_key(user_ids) do
    user_ids |> Enum.uniq() |> Enum.sort() |> Enum.join("-")
  end
end
