defmodule Campfire.Accounts.User do
  @moduledoc """
  A person or a bot. See docs/DOMAIN_API.md for the actions.
  """

  use Ash.Resource,
    otp_app: :campfire,
    domain: Campfire.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshRateLimiter, AshOban]

  alias Campfire.Accounts.User.Actions.AuthenticateBot

  alias Campfire.Accounts.User.Changes.{
    BanSessionIps,
    Deactivate,
    DestroyBans,
    DestroySessions,
    DisconnectSockets,
    EnqueueBannedContentRemoval,
    GenerateBotToken,
    GrantOpenRooms,
    HashPassword,
    NormalizeEmail,
    RemoveBannedContent,
    SaveWebhook,
    SetRole
  }

  alias Campfire.Accounts.User.Preparations.{SignInRateLimitKey, VerifyPassword}

  rate_limit do
    backend Campfire.Hammer

    # Original: 10 attempts per 3 minutes per IP. Every call counts, failed or not (no reset on success).
    action :sign_in,
      limit: 10,
      per: :timer.minutes(3),
      key: &SignInRateLimitKey.key/2
  end

  postgres do
    table "users"
    repo Campfire.Repo
  end

  # Enqueued by `Changes.EnqueueBannedContentRemoval` after the `:ban` action commits, so there
  # is no polling scheduler. The `where` stops the job if the user was unbanned meanwhile.
  oban do
    triggers do
      trigger :remove_banned_content do
        action :remove_banned_content
        queue :default
        scheduler_cron false
        where expr(status == :banned)
        max_attempts 3
        lock_for_update? false
        worker_module_name Campfire.Accounts.User.AshOban.Worker.RemoveBannedContent
        scheduler_module_name Campfire.Accounts.User.AshOban.Scheduler.RemoveBannedContent
      end
    end
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

    read :by_ids do
      description "The users with the given ids (names/avatars for rendering mentions; public)."
      argument :ids, {:array, :integer}, allow_nil?: false
      filter expr(id in ^arg(:ids))
      prepare build(select: [:id, :name, :role, :avatar_key, :updated_at])
    end

    read :for_avatar do
      description "A user's public avatar data (nothing else is loaded). No actor needed."
      get? true
      argument :id, :integer, allow_nil?: false
      filter expr(id == ^arg(:id))
      prepare build(select: [:id, :name, :role, :avatar_key, :updated_at])
    end

    read :active_by_id do
      description "The active user with that id. No actor needed."
      get? true
      argument :id, :integer, allow_nil?: false
      filter expr(id == ^arg(:id) and status == :active)
    end

    read :first_administrator do
      description "The oldest administrator (the help contact on the sign-in pages). No actor needed."
      get? true
      filter expr(role == :administrator)
      prepare build(sort: [id: :asc], limit: 1)
    end

    read :sign_in do
      description "Returns the active, non-bot user with that email and password, or nothing. Rate limited: 10 calls per 3 minutes per `ip_address`."
      get? true
      argument :email_address, :string, allow_nil?: false
      argument :password, :string, allow_nil?: false, sensitive?: true

      argument :ip_address, :string,
        description: "The client IP the rate limit is keyed on (the email address when nil)."

      filter expr(
               email_address == string_downcase(^arg(:email_address)) and status == :active and
                 role != :bot
             )

      prepare VerifyPassword
    end

    action :authenticate_bot, :struct do
      description "Returns the active bot for a `<id>-<token>` bot key, or nil."
      constraints instance_of: __MODULE__
      allow_nil? true
      argument :bot_key, :string, allow_nil?: false, sensitive?: true

      run AuthenticateBot
    end

    create :register do
      accept [:name, :email_address, :bio, :avatar_key]
      argument :password, :string, allow_nil?: false, sensitive?: true
      change set_attribute(:role, :member)
      change NormalizeEmail
      change HashPassword
      change GrantOpenRooms
    end

    create :register_administrator do
      description "First run only. Called with authorize?: false."
      accept [:name, :email_address, :bio, :avatar_key]
      argument :password, :string, allow_nil?: false, sensitive?: true
      change set_attribute(:role, :administrator)
      change NormalizeEmail
      change HashPassword
      change GrantOpenRooms
    end

    update :update_profile do
      # DeleteReplacedUpload reads the stored avatar_key.
      require_atomic? false
      accept [:name, :email_address, :bio, :avatar_key]
      argument :password, :string, sensitive?: true
      change NormalizeEmail
      change HashPassword
      change {Campfire.Changes.DeleteReplacedUpload, attribute: :avatar_key}
    end

    update :set_last_room do
      accept [:last_room_id]
    end

    update :change_role do
      argument :role, :atom, allow_nil?: false
      validate attribute_does_not_equal(:role, :bot), message: "can't be changed for a bot"
      change SetRole
    end

    update :deactivate do
      # Deactivate reads the stored email address to mangle it.
      require_atomic? false
      accept []
      change Deactivate
      change DestroySessions
      change DisconnectSockets
    end

    update :ban do
      accept []
      change set_attribute(:status, :banned)
      # BanSessionIps must run before DestroySessions (it reads the sessions' IPs)
      change BanSessionIps
      change DestroySessions
      change DisconnectSockets
      change EnqueueBannedContentRemoval
    end

    update :remove_banned_content do
      description """
      Deletes every message by a banned user, broadcasting each deletion. Only run by the
      `:remove_banned_content` Oban trigger, so it is safe to run again.
      """

      accept []
      require_atomic? false
      transaction? false
      change RemoveBannedContent
    end

    update :unban do
      accept []
      change set_attribute(:status, :active)
      change DestroyBans
    end

    create :create_bot do
      accept [:name, :avatar_key]
      argument :webhook_url, :string
      change set_attribute(:role, :bot)
      change GenerateBotToken
      change GrantOpenRooms
      change SaveWebhook
    end

    update :update_bot do
      # DeleteReplacedUpload reads the stored avatar_key.
      require_atomic? false
      accept [:name, :avatar_key]
      argument :webhook_url, :string
      validate attribute_equals(:role, :bot)
      change {Campfire.Changes.DeleteReplacedUpload, attribute: :avatar_key}
      change SaveWebhook
    end

    update :reset_bot_key do
      accept []
      validate attribute_equals(:role, :bot)
      change GenerateBotToken
    end
  end

  policies do
    # The Oban worker reads the user and runs `:remove_banned_content` without an actor.
    bypass AshOban.Checks.AshObanInteraction do
      authorize_if always()
    end

    policy action([:sign_in, :authenticate_bot, :register]) do
      authorize_if always()
    end

    policy action([:read, :people]) do
      authorize_if actor_present()
    end

    # Used before anyone is signed in (avatars, transfer links, the sign-in page) or without an
    # actor (rendering mentions).
    policy action([:by_ids, :for_avatar, :active_by_id, :first_administrator]) do
      authorize_if always()
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
