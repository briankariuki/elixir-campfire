defmodule Campfire.Chat.Room do
  @moduledoc """
  An open, closed or direct room. See docs/DOMAIN_API.md for the actions.
  """

  use Ash.Resource,
    otp_app: :campfire,
    domain: Campfire.Chat,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  require Ash.Query

  alias Campfire.Accounts.User
  alias Campfire.Chat.Room.{Actions, Changes}

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

    read :oldest_for_user do
      description "The actor's oldest room (all kinds): where `/` lands without a valid last room."
      get? true
      prepare build(sort: [inserted_at: :asc, id: :asc], limit: 1)
    end

    create :create_open do
      accept [:name]
      change set_attribute(:kind, :open)
      change relate_actor(:creator)
      change Changes.GrantActiveUsers
      notifiers [Campfire.Notifiers.Fanout]
    end

    create :create_closed do
      accept [:name]
      argument :user_ids, {:array, :integer}, default: []
      change set_attribute(:kind, :closed)
      change relate_actor(:creator)
      change Changes.ReviseMembers
      notifiers [Campfire.Notifiers.Fanout]
    end

    create :create_direct do
      description "Internal: use Campfire.Chat.find_or_create_direct_room/2."
      accept []
      argument :user_ids, {:array, :integer}, allow_nil?: false
      change set_attribute(:kind, :direct)
      change relate_actor(:creator)
      change Changes.SetDirectKey
      change Changes.GrantDirectUsers
      notifiers [Campfire.Notifiers.Fanout]
    end

    action :find_or_create_direct, :struct do
      description "Finds the direct room for exactly these users (plus the actor), or creates it."
      constraints instance_of: __MODULE__
      argument :user_ids, {:array, :integer}, allow_nil?: false
      run Actions.FindOrCreateDirect
    end

    update :update_open do
      accept [:name]

      validate attribute_does_not_equal(:kind, :direct),
        message: "can't be changed for a direct room"

      change set_attribute(:kind, :open)
      change Changes.GrantActiveUsers
      notifiers [Campfire.Notifiers.Fanout]
    end

    update :update_closed do
      accept [:name]
      argument :user_ids, {:array, :integer}, default: []

      validate attribute_does_not_equal(:kind, :direct),
        message: "can't be changed for a direct room"

      change set_attribute(:kind, :closed)
      change Changes.ReviseMembers
      notifiers [Campfire.Notifiers.Fanout]
    end

    update :touch do
      description "Internal: bumps `updated_at` when a message is created or edited."
      accept []
      change atomic_update(:updated_at, expr(now()))
    end

    destroy :destroy do
      primary? true
      description "Deletes the room with its memberships, messages, boosts and attachment files."
      # DestroyContents reads the room's members and attachments before they cascade away.
      require_atomic? false
      change Changes.DestroyContents
      notifiers [Campfire.Notifiers.Fanout]
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

  @doc "The ids of the active users (bots included): who an open room is granted to."
  def active_user_ids do
    # Internal lookup for granting memberships, not a user-facing read.
    User
    |> Ash.Query.filter(status == :active)
    |> Ash.Query.select([:id])
    |> Ash.read!(authorize?: false)
    |> Enum.map(& &1.id)
  end

  @doc "Those of `user_ids` that are existing users (unknown ids are dropped)."
  def existing_user_ids(user_ids) do
    user_ids = Enum.uniq(user_ids)

    User
    |> Ash.Query.filter(id in ^user_ids)
    |> Ash.Query.select([:id])
    |> Ash.read!(authorize?: false)
    |> Enum.map(& &1.id)
  end

  @doc "The canonical key of a direct room: the sorted, unique member ids joined with `-`."
  def direct_key(user_ids) do
    user_ids |> Enum.uniq() |> Enum.sort() |> Enum.join("-")
  end
end
