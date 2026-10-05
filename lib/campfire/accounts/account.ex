defmodule Campfire.Accounts.Account do
  @moduledoc "The single account row: name, logo, join code and settings."

  use Ash.Resource,
    otp_app: :campfire,
    domain: Campfire.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "accounts"
    repo Campfire.Repo
  end

  actions do
    defaults [:read]

    read :get do
      get? true
    end

    create :create do
      accept [:name]
      change set_attribute(:join_code, &__MODULE__.generate_join_code/0)
    end

    update :update do
      require_atomic? false
      accept [:name, :logo_key, :restrict_room_creation_to_administrators]
      change {Campfire.Changes.DeleteReplacedUpload, attribute: :logo_key}
    end

    update :reset_join_code do
      require_atomic? false
      accept []
      change set_attribute(:join_code, &__MODULE__.generate_join_code/0)
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type([:create, :update]) do
      authorize_if actor_attribute_equals(:role, :administrator)
    end
  end

  attributes do
    integer_primary_key :id

    attribute :name, :string do
      allow_nil? false
      default "Campfire"
      public? true
    end

    attribute :join_code, :string do
      allow_nil? false
      public? true
    end

    attribute :logo_key, :string, public?: true

    attribute :restrict_room_creation_to_administrators, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :singleton_guard, :integer do
      allow_nil? false
      default 0
    end

    timestamps()
  end

  identities do
    identity :singleton, [:singleton_guard]
  end

  @doc "12 random alphanumerics in groups of four, e.g. `CRMu-l8Ge-KB9B`."
  def generate_join_code do
    12
    |> Campfire.Random.alphanumeric()
    |> String.graphemes()
    |> Enum.chunk_every(4)
    |> Enum.map_join("-", &Enum.join/1)
  end
end
