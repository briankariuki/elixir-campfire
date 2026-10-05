defmodule Campfire.Accounts.User do
  @moduledoc """
  A person or a bot. See docs/DOMAIN_API.md for the actions.
  """

  use Ash.Resource,
    otp_app: :campfire,
    domain: Campfire.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Campfire.Accounts.UserLifecycle

  postgres do
    table "users"
    repo Campfire.Repo
  end

  actions do
    defaults [:read]

    read :people do
      description "Active people (no bots by default), ordered by name."
      argument :include_banned, :boolean, default: false
      argument :include_bots, :boolean, default: false

      filter expr(
               (status == :active or (^arg(:include_banned) and status == :banned)) and
                 (role != :bot or ^arg(:include_bots))
             )

      prepare build(sort: [sort_name: :asc, id: :asc])
    end

    read :bots do
      description "Active bots with their webhook loaded, ordered by name."
      filter expr(role == :bot and status == :active)
      prepare build(sort: [sort_name: :asc, id: :asc], load: [:webhook])
    end

    read :sign_in do
      description "Returns the active, non-bot user with that email and password, or nothing."
      get? true
      argument :email_address, :string, allow_nil?: false
      argument :password, :string, allow_nil?: false, sensitive?: true

      filter expr(
               email_address == string_downcase(^arg(:email_address)) and status == :active and
                 role != :bot
             )

      prepare &UserLifecycle.verify_password/2
    end

    action :authenticate_bot, :struct do
      description "Returns the active bot for a `<id>-<token>` bot key, or nil."
      constraints instance_of: __MODULE__
      allow_nil? true
      argument :bot_key, :string, allow_nil?: false, sensitive?: true

      run fn input, _context ->
        {:ok, UserLifecycle.find_bot_by_key(input.arguments.bot_key)}
      end
    end

    create :register do
      accept [:name, :email_address, :bio, :avatar_key]
      argument :password, :string, allow_nil?: false, sensitive?: true
      change set_attribute(:role, :member)
      change &UserLifecycle.normalize_email/2
      change &UserLifecycle.hash_password/2
      change after_action(&UserLifecycle.grant_open_rooms/3)
    end

    create :register_administrator do
      description "First run only. Called with authorize?: false."
      accept [:name, :email_address, :bio, :avatar_key]
      argument :password, :string, allow_nil?: false, sensitive?: true
      change set_attribute(:role, :administrator)
      change &UserLifecycle.normalize_email/2
      change &UserLifecycle.hash_password/2
      change after_action(&UserLifecycle.grant_open_rooms/3)
    end

    update :update_profile do
      require_atomic? false
      accept [:name, :email_address, :bio, :avatar_key]
      argument :password, :string, sensitive?: true
      change &UserLifecycle.normalize_email/2
      change &UserLifecycle.hash_password/2
      change {Campfire.Changes.DeleteReplacedUpload, attribute: :avatar_key}
    end

    update :set_last_room do
      accept [:last_room_id]
    end

    update :change_role do
      require_atomic? false
      argument :role, :atom, allow_nil?: false
      change &UserLifecycle.change_role/2
    end

    update :deactivate do
      require_atomic? false
      accept []
      change &UserLifecycle.deactivate/2
    end

    update :ban do
      require_atomic? false
      accept []
      change &UserLifecycle.ban/2
    end

    update :unban do
      require_atomic? false
      accept []
      change &UserLifecycle.unban/2
    end

    create :create_bot do
      accept [:name, :avatar_key]
      argument :webhook_url, :string
      change set_attribute(:role, :bot)
      change set_attribute(:bot_token, &UserLifecycle.generate_bot_token/0)
      change after_action(&UserLifecycle.grant_open_rooms/3)
      change after_action(&UserLifecycle.save_webhook/3)
    end

    update :update_bot do
      require_atomic? false
      accept [:name, :avatar_key]
      argument :webhook_url, :string
      validate attribute_equals(:role, :bot)
      change {Campfire.Changes.DeleteReplacedUpload, attribute: :avatar_key}
      change after_action(&UserLifecycle.save_webhook/3)
    end

    update :reset_bot_key do
      require_atomic? false
      accept []
      validate attribute_equals(:role, :bot)
      change set_attribute(:bot_token, &UserLifecycle.generate_bot_token/0)
    end
  end

  policies do
    policy action([:sign_in, :authenticate_bot, :register]) do
      authorize_if always()
    end

    policy action([:read, :people]) do
      authorize_if actor_present()
    end

    policy action([:update_profile, :set_last_room]) do
      authorize_if expr(id == ^actor(:id))
    end

    policy action([
             :bots,
             :change_role,
             :deactivate,
             :ban,
             :unban,
             :create_bot,
             :update_bot,
             :reset_bot_key
           ]) do
      authorize_if actor_attribute_equals(:role, :administrator)
    end

    policy action([:ban, :deactivate]) do
      forbid_if expr(id == ^actor(:id))
      authorize_if always()
    end

    # :register_administrator is internal (first run) and has no policy, so it is forbidden
    # unless called with authorize?: false.
  end

  attributes do
    integer_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :email_address, :string, public?: true

    attribute :password_hash, :string do
      sensitive? true
    end

    attribute :bio, :string, public?: true

    attribute :role, :atom do
      allow_nil? false
      default :member
      constraints one_of: [:member, :administrator, :bot]
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      default :active
      constraints one_of: [:active, :deactivated, :banned]
      public? true
    end

    attribute :bot_token, :string do
      sensitive? true
    end

    attribute :avatar_key, :string, public?: true
    attribute :last_room_id, :integer, public?: true

    timestamps()
  end

  relationships do
    has_many :memberships, Campfire.Chat.Membership

    many_to_many :rooms, Campfire.Chat.Room do
      through Campfire.Chat.Membership
      source_attribute_on_join_resource :user_id
      destination_attribute_on_join_resource :room_id
    end

    has_many :sessions, Campfire.Accounts.Session
    has_many :bans, Campfire.Accounts.Ban
    has_one :webhook, Campfire.Accounts.Webhook
  end

  calculations do
    calculate :sort_name, :string, expr(string_downcase(name))

    calculate :initials, :string, fn records, _context ->
      Enum.map(records, &initials/1)
    end

    calculate :bot_key, :string, fn records, _context ->
      Enum.map(records, &bot_key/1)
    end
  end

  identities do
    identity :unique_email, [:email_address]
    identity :unique_bot_token, [:bot_token]
  end

  @doc "The first letter of each word of the name, e.g. `\"JF\"` for \"Jason Fried\"."
  def initials(%{name: name}) when is_binary(name) do
    ~r/\b\w/u |> Regex.scan(name) |> List.flatten() |> Enum.join()
  end

  def initials(_), do: ""

  @doc "The bot key used in bot API URLs: `\"<id>-<bot_token>\"`. nil for non-bots."
  def bot_key(%{id: id, bot_token: token}) when is_binary(token), do: "#{id}-#{token}"
  def bot_key(_), do: nil

  def administrator?(%{role: :administrator}), do: true
  def administrator?(_), do: false

  def bot?(%{role: :bot}), do: true
  def bot?(_), do: false

  def active?(%{status: :active}), do: true
  def active?(_), do: false

  @doc "Admins can administer anything; others only records they created."
  def can_administer?(%{role: :administrator}, _record), do: true
  def can_administer?(%{id: id}, %{creator_id: id}), do: true
  def can_administer?(_, _), do: false
end
