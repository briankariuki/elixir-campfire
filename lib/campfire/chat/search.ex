defmodule Campfire.Chat.Search do
  @moduledoc "A user's recent search query. Only the 10 most recent are kept."

  use Ash.Resource,
    otp_app: :campfire,
    domain: Campfire.Chat,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  require Ash.Query

  alias Campfire.Chat.Search.{Actions, Changes}

  @keep 10

  postgres do
    table "searches"
    repo Campfire.Repo

    references do
      reference :user, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    read :recent do
      description "The actor's recent searches, newest first."
      filter expr(user_id == ^actor(:id))
      prepare build(sort: [updated_at: :desc, id: :desc])
    end

    create :record do
      description "Records a query for the actor (touching it if it exists); keeps the 10 newest."
      accept [:query]
      upsert? true
      upsert_identity :unique_user_query
      upsert_fields [:updated_at]
      change relate_actor(:user)
      change Changes.PruneOld
    end

    destroy :destroy do
      description "Internal: used in bulk by `prune/1` and `clear_for/1`."
    end

    action :clear do
      description "Deletes all of the actor's searches."
      run Actions.Clear
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(user_id == ^actor(:id))
    end

    policy action([:record, :clear]) do
      authorize_if actor_present()
    end
  end

  attributes do
    integer_primary_key :id

    attribute :query, :string do
      allow_nil? false
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :user, Campfire.Accounts.User do
      allow_nil? false
      attribute_type :integer
      public? true
    end
  end

  identities do
    identity :unique_user_query, [:user_id, :query]
  end

  # `prune/1` and `clear_for/1` are internal housekeeping scoped to one user id, so they run
  # with `authorize?: false`: the callers (the `:record` and `:clear` actions, user
  # deactivation) have already decided who may do it.

  @doc false
  def prune(user_id) do
    keep =
      __MODULE__
      |> Ash.Query.filter(user_id == ^user_id)
      |> Ash.Query.sort(updated_at: :desc, id: :desc)
      |> Ash.Query.limit(@keep)
      |> Ash.Query.select([:id])
      |> Ash.read!(authorize?: false)
      |> Enum.map(& &1.id)

    __MODULE__
    |> Ash.Query.filter(user_id == ^user_id and id not in ^keep)
    |> Ash.bulk_destroy!(:destroy, %{}, authorize?: false)
  end

  @doc false
  def clear_for(user_id) do
    __MODULE__
    |> Ash.Query.filter(user_id == ^user_id)
    |> Ash.bulk_destroy!(:destroy, %{}, authorize?: false)
  end
end
