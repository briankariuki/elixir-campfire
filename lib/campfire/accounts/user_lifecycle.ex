defmodule Campfire.Accounts.UserLifecycle do
  @moduledoc false
  # The changes and helpers behind the User actions: passwords, bot keys, deactivation and bans.

  import Ecto.Query
  require Ash.Query

  alias Ash.Changeset
  alias Campfire.Accounts.{Ban, Session, User, Webhook}
  alias Campfire.{Async, Broadcast, Repo}
  alias Campfire.Chat.{Membership, Message, Search}

  ## Passwords and emails

  def hash_password(changeset, _context) do
    case Changeset.get_argument(changeset, :password) do
      password when is_binary(password) and password != "" ->
        Changeset.force_change_attribute(
          changeset,
          :password_hash,
          Bcrypt.hash_pwd_salt(password)
        )

      _ ->
        changeset
    end
  end

  def normalize_email(changeset, _context) do
    case Changeset.get_attribute(changeset, :email_address) do
      email when is_binary(email) ->
        Changeset.force_change_attribute(
          changeset,
          :email_address,
          email |> String.trim() |> String.downcase()
        )

      _ ->
        changeset
    end
  end

  def verify_password(query, _context) do
    Ash.Query.after_action(query, fn query, users ->
      password = Ash.Query.get_argument(query, :password)

      case users do
        [%User{password_hash: hash} = user] when is_binary(hash) ->
          if Bcrypt.verify_pass(password, hash), do: {:ok, [user]}, else: {:ok, []}

        _ ->
          Bcrypt.no_user_verify()
          {:ok, []}
      end
    end)
  end

  ## Bots

  def generate_bot_token, do: Campfire.Random.alphanumeric(12)

  def find_bot_by_key(bot_key) when is_binary(bot_key) do
    with [id_part, token] when token != "" <- String.split(bot_key, "-", parts: 2),
         {id, ""} <- Integer.parse(id_part),
         {:ok, %User{bot_token: bot_token} = bot} when is_binary(bot_token) <-
           User
           |> Ash.Query.filter(id == ^id and role == :bot and status == :active)
           |> Ash.read_one(authorize?: false),
         true <- Plug.Crypto.secure_compare(bot_token, token) do
      bot
    else
      _ -> nil
    end
  end

  def find_bot_by_key(_), do: nil

  # An omitted webhook_url leaves the webhook alone; nil or blank deletes it.
  def save_webhook(changeset, user, _context) do
    case Changeset.fetch_argument(changeset, :webhook_url) do
      :error ->
        {:ok, user}

      {:ok, url} ->
        url = url |> to_string() |> String.trim()

        if url == "" do
          Repo.delete_all(from w in Webhook, where: w.user_id == ^user.id)
          {:ok, user}
        else
          with {:ok, _webhook} <-
                 Webhook
                 |> Changeset.for_create(:create, %{user_id: user.id, url: url})
                 |> Ash.create(authorize?: false) do
            {:ok, user}
          end
        end
    end
  end

  ## Memberships

  def grant_open_rooms(_changeset, user, _context) do
    Membership.grant_open_rooms(user.id)
    {:ok, user}
  end

  ## Roles, deactivation and bans

  def change_role(changeset, _context) do
    if changeset.data.role == :bot do
      Changeset.add_error(changeset, field: :role, message: "can't be changed for a bot")
    else
      role =
        if Changeset.get_argument(changeset, :role) == :administrator,
          do: :administrator,
          else: :member

      Changeset.change_attribute(changeset, :role, role)
    end
  end

  def deactivate(changeset, _context) do
    email = changeset.data.email_address

    changeset
    |> Changeset.change_attribute(:status, :deactivated)
    |> then(fn changeset ->
      if is_binary(email) and email =~ "@" do
        mangled = String.replace(email, "@", "-deactivated-#{Ecto.UUID.generate()}@")
        Changeset.change_attribute(changeset, :email_address, mangled)
      else
        changeset
      end
    end)
    |> Changeset.after_action(fn _changeset, user ->
      Membership.revoke_all_except_direct(user.id)
      Repo.delete_all(from s in Session, where: s.user_id == ^user.id)
      Repo.delete_all(from s in Search, where: s.user_id == ^user.id)
      {:ok, user}
    end)
    |> disconnect_after_transaction()
  end

  def ban(changeset, _context) do
    changeset
    |> Changeset.change_attribute(:status, :banned)
    |> Changeset.after_action(fn _changeset, user ->
      ban_session_ips(user.id)
      Repo.delete_all(from s in Session, where: s.user_id == ^user.id)
      {:ok, user}
    end)
    |> disconnect_after_transaction()
    |> Changeset.after_transaction(fn
      _changeset, {:ok, user} ->
        Async.run(fn -> Message.remove_all_by_creator(user.id) end)
        {:ok, user}

      _changeset, error ->
        error
    end)
  end

  def unban(changeset, _context) do
    changeset
    |> Changeset.change_attribute(:status, :active)
    |> Changeset.after_action(fn _changeset, user ->
      Repo.delete_all(from b in Ban, where: b.user_id == ^user.id)
      {:ok, user}
    end)
  end

  defp disconnect_after_transaction(changeset) do
    Changeset.after_transaction(changeset, fn
      _changeset, {:ok, user} ->
        Broadcast.disconnect_user(user.id)
        {:ok, user}

      _changeset, error ->
        error
    end)
  end

  defp ban_session_ips(user_id) do
    from(s in Session,
      where: s.user_id == ^user_id and not is_nil(s.ip_address),
      distinct: true,
      select: s.ip_address
    )
    |> Repo.all()
    |> Enum.filter(&Ban.public_ip?/1)
    |> Enum.each(fn ip ->
      Ban
      |> Changeset.for_create(:create, %{user_id: user_id, ip_address: ip})
      |> Ash.create!(authorize?: false)
    end)
  end
end
