defmodule Campfire.Accounts.Webhook do
  @moduledoc """
  A bot's webhook URL. Managed through the bot actions (`create_bot`, `update_bot`); delivery
  lives in `Campfire.Webhooks`.
  """

  use Ash.Resource,
    otp_app: :campfire,
    domain: Campfire.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "webhooks"
    repo Campfire.Repo

    references do
      reference :user, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :create do
      description "Creates or replaces the bot's webhook (upsert on user_id)."
      accept [:user_id, :url]
      upsert? true
      upsert_identity :unique_user
      upsert_fields [:url, :updated_at]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :administrator)
    end
  end

  validations do
    validate match(:url, ~r/\Ahttps?:\/\/\S+\z/), message: "must be an http(s) URL"
  end

  attributes do
    integer_primary_key :id

    attribute :url, :string do
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
    identity :unique_user, [:user_id]
  end
end
