defmodule Campfire.Accounts do
  @moduledoc """
  The account, users (people and bots), sessions, bans and webhooks.

  See docs/DOMAIN_API.md for the full list of functions.
  """

  use Ash.Domain, otp_app: :campfire

  require Ash.Query

  alias Campfire.Accounts.{Account, Ban, Session, User}
  alias Campfire.Repo

  resources do
    resource Account do
      define :get_account, action: :get, not_found_error?: false
      define :update_account, action: :update
      define :reset_join_code, action: :reset_join_code
    end

    resource User do
      define :get_user, action: :read, get_by: [:id]
      define :list_users, action: :people
      define :list_bots, action: :bots

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
    end

    resource Ban
    resource Campfire.Accounts.Webhook
  end

  @doc """
  First run: creates the account, an administrator and the open room "All Talk", in one
  transaction. Returns `{:ok, %{account: account, user: user, room: room}}`, or
  `{:error, :already_set_up}` when an account exists.

  `attrs`: `:name`, `:email_address`, `:password`, optional `:avatar_key`.
  """
  def first_run(attrs) do
    Repo.transaction(fn ->
      if get_account!(authorize?: false), do: Repo.rollback(:already_set_up)

      with {:ok, account} <-
             Account
             |> Ash.Changeset.for_create(:create, %{})
             |> Ash.create(authorize?: false),
           {:ok, user} <-
             User
             |> Ash.Changeset.for_create(:register_administrator, attrs)
             |> Ash.create(authorize?: false),
           {:ok, room} <-
             Campfire.Chat.create_open_room("All Talk",
               actor: user,
               authorize?: false,
               context: %{warn_on_transaction_hooks?: false}
             ) do
        %{account: account, user: user, room: room}
      else
        {:error, error} -> Repo.rollback(error)
      end
    end)
  end

  @doc "Raising version of `first_run/1`."
  def first_run!(attrs) do
    case first_run(attrs) do
      {:ok, result} -> result
      {:error, error} -> raise "first run failed: #{inspect(error)}"
    end
  end

  @doc "Whether first run has happened (an account exists)."
  def set_up?, do: get_account!(authorize?: false) != nil

  @doc "Whether `code` is the account's join code."
  def valid_join_code?(code) when is_binary(code) do
    case get_account!(authorize?: false) do
      %Account{join_code: join_code} -> Plug.Crypto.secure_compare(join_code, code)
      nil -> false
    end
  end

  def valid_join_code?(_), do: false

  @doc """
  The session for a token, with its (active) user loaded, or nil. No actor needed.
  """
  def get_session_by_token(token) when is_binary(token) do
    Session
    |> Ash.Query.for_read(:by_token, %{token: token})
    |> Ash.read_one!(authorize?: false)
  end

  def get_session_by_token(_), do: nil

  @doc """
  Refreshes the session's `last_active_at`, IP and user agent, but only when it is more than an
  hour old (throttles writes). Returns `{:ok, session}`.
  """
  def touch_session(%Session{} = session, attrs \\ %{}) do
    if Session.stale?(session) do
      session
      |> Ash.Changeset.for_update(:touch, attrs)
      |> Ash.update(authorize?: false)
    else
      {:ok, session}
    end
  end

  @doc "Whether requests from `ip` are banned."
  def banned_ip?(ip) when is_binary(ip) do
    Ban
    |> Ash.Query.filter(ip_address == ^ip)
    |> Ash.exists?(authorize?: false)
  end

  def banned_ip?(_), do: false
end
