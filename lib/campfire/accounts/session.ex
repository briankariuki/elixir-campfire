defmodule Campfire.Accounts.Session do
  @moduledoc "A signed-in browser. The token is stored in the Plug session as `:session_token`."

  use Ash.Resource,
    otp_app: :campfire,
    domain: Campfire.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Campfire.Accounts.Session.Changes.{DisconnectUser, TouchIfStale}

  @refresh_after_seconds 3600

  postgres do
    table "sessions"
    repo Campfire.Repo

    references do
      reference :user, on_delete: :delete
    end

    # Looked up and deleted by user on deactivate, ban and "log out everywhere"; Postgres
    # doesn't index foreign keys on its own.
    custom_indexes do
      index [:user_id]
    end
  end

  actions do
    defaults [:read]

    read :by_token do
      description "The session with that token, if its user is active, with the user loaded."
      get? true
      argument :token, :string, allow_nil?: false, sensitive?: true
      filter expr(token == ^arg(:token) and user.status == :active)
      prepare build(load: [:user])
    end

    create :create do
      description "Starts a session for the actor."
      accept [:ip_address, :user_agent]
      change relate_actor(:user)
      change set_attribute(:token, &Campfire.Random.url_token/0)
      change set_attribute(:last_active_at, &DateTime.utc_now/0)
    end

    update :touch do
      description "Refreshes last_active_at, IP and user agent, but only if the session is over an hour old."
      # TouchIfStale reads the stored last_active_at, and skips the write entirely when fresh.
      require_atomic? false
      accept [:ip_address, :user_agent]
      change TouchIfStale
    end

    destroy :destroy do
      primary? true
      description "Logs out: deletes the session and disconnects the user's sockets."

      change DisconnectUser
    end
  end

  policies do
    policy action(:by_token) do
      authorize_if always()
    end

    policy action(:create) do
      authorize_if actor_present()
    end

    policy action([:read, :touch, :destroy]) do
      authorize_if expr(user_id == ^actor(:id))
    end
  end

  attributes do
    integer_primary_key :id

    attribute :token, :string do
      allow_nil? false
      sensitive? true
    end

    attribute :ip_address, :string, public?: true
    attribute :user_agent, :string, public?: true

    attribute :last_active_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :user, Campfire.Accounts.User do
      allow_nil? false
      attribute_type :integer
    end
  end

  identities do
    identity :unique_token, [:token]
  end

  @doc "Whether `last_active_at` is old enough (1 hour) to be refreshed by `touch`."
  def stale?(%__MODULE__{last_active_at: last_active_at}) do
    DateTime.diff(DateTime.utc_now(), last_active_at, :second) >= @refresh_after_seconds
  end
end
