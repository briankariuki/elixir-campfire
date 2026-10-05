defmodule Campfire.Accounts do
  @moduledoc """
  The account, users (people and bots), sessions, bans and webhooks.

  See docs/DOMAIN_API.md for the full list of functions. Every function here is a code
  interface for a resource action.
  """

  use Ash.Domain, otp_app: :campfire, extensions: [AshAdmin.Domain]

  alias Campfire.Accounts.{Account, Ban, Session, User}

  admin do
    show? true
  end

  resources do
    resource Account do
      define :get_account, action: :get, not_found_error?: false
      define :update_account, action: :update
      define :reset_join_code, action: :reset_join_code
      define :first_run, action: :first_run
      define :set_up?, action: :set_up?
      define :valid_join_code?, action: :valid_join_code?, args: [:code]
    end

    resource User do
      define :get_user, action: :read, get_by: [:id]
      define :list_users, action: :people
      define :list_bots, action: :bots
      define :list_users_by_ids, action: :by_ids, args: [:ids]
      define :get_user_for_avatar, action: :for_avatar, args: [:id], not_found_error?: false
      define :get_active_user, action: :active_by_id, args: [:id], not_found_error?: false
      define :first_administrator, action: :first_administrator, not_found_error?: false

      define :sign_in,
        action: :sign_in,
        args: [:email_address, :password],
        not_found_error?: false

      define :authenticate_bot, action: :authenticate_bot, args: [:bot_key]
      define :register_user, action: :register
      define :update_profile, action: :update_profile
      define :set_last_room, action: :set_last_room, args: [:last_room_id]
      define :change_role, action: :change_role, args: [:role]
      define :deactivate_user, action: :deactivate
      define :ban_user, action: :ban
      define :unban_user, action: :unban
      define :create_bot, action: :create_bot
      define :update_bot, action: :update_bot
      define :reset_bot_key, action: :reset_bot_key
    end

    resource Session do
      define :create_session, action: :create
      define :destroy_session, action: :destroy

      # The token is the credential. No actor exists yet, and the `user` load is authorized
      # against User's read policy (actor_present), so it must be skipped here.
      define :get_session_by_token,
        action: :by_token,
        args: [:token],
        not_found_error?: false,
        default_options: [authorize?: false]

      define :touch_session, action: :touch
    end

    resource Ban do
      define :banned_ip?, action: :banned_ip?, args: [:ip_address]
    end

    resource Campfire.Accounts.Webhook
  end
end
