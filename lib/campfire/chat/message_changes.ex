defmodule Campfire.Chat.MessageChanges do
  @moduledoc false
  # The changes behind the Message actions: mentions, unread marks, broadcasts and webhooks.

  import Ecto.Query

  require Ash.Query

  alias Ash.Changeset
  alias Campfire.{Broadcast, Presence, Repo, Uploads}
  alias Campfire.Chat.{Membership, Mentions}

  @loads [:creator, boosts: [:booster]]

  @doc "What broadcasts and pages load on messages."
  def loads, do: @loads

  def set_room(changeset, _context) do
    case Changeset.get_argument(changeset, :room) do
      %{id: room_id} -> Changeset.force_change_attribute(changeset, :room_id, room_id)
      _ -> changeset
    end
  end

  def ensure_client_message_id(changeset, _context) do
    case Changeset.get_attribute(changeset, :client_message_id) do
      id when is_binary(id) and id != "" -> changeset
      _ -> Changeset.force_change_attribute(changeset, :client_message_id, Ecto.UUID.generate())
    end
  end

  def validate_content(changeset, _context) do
    body = Changeset.get_attribute(changeset, :body)
    attachment_key = Changeset.get_attribute(changeset, :attachment_key)

    if (is_binary(body) and String.trim(body) != "") or is_binary(attachment_key) do
      :ok
    else
      {:error, field: :body, message: "can't be blank"}
    end
  end

  def resolve_mentions(changeset, _context) do
    Changeset.before_action(changeset, fn changeset ->
      room_id = Changeset.get_attribute(changeset, :room_id)
      body = Changeset.get_attribute(changeset, :body)
      ids = Mentions.mentioned_ids(body, Mentions.room_members(room_id))
      Changeset.force_change_attribute(changeset, :mentioned_user_ids, ids)
    end)
  end

  def after_create(changeset, _context) do
    changeset
    |> Changeset.after_action(fn _changeset, message ->
      touch_room(message.room_id)
      mark_unread(message)
      {:ok, Ash.load!(message, @loads, authorize?: false)}
    end)
    |> Changeset.after_transaction(fn
      changeset, {:ok, message} ->
        Broadcast.room(message.room_id, {:message_created, message})
        Broadcast.users(Membership.member_ids(message.room_id), {:room_unread, message.room_id})

        if Changeset.get_argument(changeset, :deliver_webhooks?) != false do
          Campfire.Webhooks.deliver_for_message(message, Changeset.get_argument(changeset, :room))
        end

        {:ok, message}

      _changeset, error ->
        error
    end)
  end

  def after_update(changeset, _context) do
    changeset
    |> Changeset.after_action(fn _changeset, message ->
      touch_room(message.room_id)
      {:ok, Ash.load!(message, @loads, authorize?: false, reuse_values?: false)}
    end)
    |> Changeset.after_transaction(fn
      _changeset, {:ok, message} ->
        Broadcast.room(message.room_id, {:message_updated, message})
        {:ok, message}

      _changeset, error ->
        error
    end)
  end

  def after_destroy(changeset, _context) do
    Changeset.after_transaction(changeset, fn
      _changeset, {:ok, message} ->
        Uploads.delete(message.attachment_key)
        Broadcast.room(message.room_id, {:message_deleted, message})
        {:ok, message}

      _changeset, error ->
        error
    end)
  end

  def prepare_search(query, _context) do
    terms =
      query
      |> Ash.Query.get_argument(:query)
      |> to_string()
      |> then(&Regex.replace(~r/[^\p{L}\p{N}_]+/u, &1, " "))
      |> String.trim()

    if terms == "" do
      Ash.Query.filter(query, false)
    else
      query
      |> Ash.Query.filter(fragment("search_vector @@ plainto_tsquery('english', ?)", ^terms))
      |> Ash.Query.sort(inserted_at: :desc, id: :desc)
      |> Ash.Query.limit(100)
      |> Ash.Query.load([:creator, :room])
      |> Ash.Query.after_action(fn _query, messages -> {:ok, Enum.reverse(messages)} end)
    end
  end

  # Set unread_at on the members who aren't the author, aren't invisible and aren't present.
  defp mark_unread(message) do
    present_ids = Presence.present_user_ids(message.room_id)
    unread_at = DateTime.to_naive(message.inserted_at)

    from(m in "memberships",
      where:
        m.room_id == ^message.room_id and m.user_id != ^message.creator_id and
          m.involvement != "invisible" and m.user_id not in ^present_ids
    )
    |> Repo.update_all(set: [unread_at: unread_at, updated_at: NaiveDateTime.utc_now()])
  end

  defp touch_room(room_id) do
    from(r in "rooms", where: r.id == ^room_id)
    |> Repo.update_all(set: [updated_at: NaiveDateTime.utc_now()])
  end
end
