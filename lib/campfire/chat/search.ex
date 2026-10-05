defmodule Campfire.Chat.Search do
  @moduledoc "A user's recent search query. Only the 10 most recent are kept."

  use Ash.Resource,
    otp_app: :campfire,
    domain: Campfire.Chat,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  import Ecto.Query

  alias Campfire.Repo

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

      change after_action(fn _changeset, search, _context ->
               __MODULE__.prune(search.user_id)
               {:ok, search}
             end)
    end

    action :clear do
      description "Deletes all of the actor's searches."

      run fn _input, context ->
        __MODULE__.clear_for(context.actor.id)
        :ok
      end
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

  @doc false
  def prune(user_id) do
    keep =
      from s in __MODULE__,
        where: s.user_id == ^user_id,
        order_by: [desc: s.updated_at, desc: s.id],
        limit: @keep,
        select: s.id

    from(s in __MODULE__, where: s.user_id == ^user_id and s.id not in subquery(keep))
    |> Repo.delete_all()
  end

  @doc false
  def clear_for(user_id) do
    Repo.delete_all(from s in __MODULE__, where: s.user_id == ^user_id)
  end
end
