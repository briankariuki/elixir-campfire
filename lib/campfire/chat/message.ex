defmodule Campfire.Chat.Message do
  @moduledoc """
  A chat message: a plain-text body and/or one attachment. See docs/DOMAIN_API.md.
  """

  use Ash.Resource,
    otp_app: :campfire,
    domain: Campfire.Chat,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  require Ash.Query

  alias Campfire.Chat.Changes.BroadcastAfterCommit
  alias Campfire.Chat.Message.{Changes, Validations}

  @page_size 40
  @loads [:creator, boosts: [:booster]]

  postgres do
    table "messages"
    repo Campfire.Repo

    references do
      reference :room, on_delete: :delete
      reference :creator, on_delete: :delete
    end

    custom_indexes do
      index [:room_id, :inserted_at, :id]
      index [:creator_id]
    end

    custom_statements do
      statement :search_vector do
        up """
        ALTER TABLE messages ADD COLUMN search_vector tsvector
          GENERATED ALWAYS AS (
            to_tsvector(
              'english',
              coalesce(body, '') || ' ' ||
                regexp_replace(coalesce(attachment_filename, ''), '[^[:alnum:]]+', ' ', 'g')
            )
          ) STORED
        """

        down "ALTER TABLE messages DROP COLUMN search_vector"
      end

      statement :search_vector_index do
        up "CREATE INDEX messages_search_vector_index ON messages USING GIN (search_vector)"
        down "DROP INDEX messages_search_vector_index"
      end
    end
  end

  actions do
    defaults [:read]

    action :page, {:array, :struct} do
      description """
      A page of 40 messages in a room, ascending by (inserted_at, id), with creator and
      boosts (with booster) loaded. Pass one of before/after/around (message ids), or nothing
      for the last page.
      """

      constraints items: [instance_of: __MODULE__]
      argument :room_id, :integer, allow_nil?: false
      argument :before, :integer
      argument :after, :integer
      argument :around, :integer
      run &Campfire.Chat.Pagination.run/2
    end

    read :search do
      description "The last 100 messages in the actor's rooms matching the query, ascending."
      argument :query, :string, allow_nil?: false
      prepare Campfire.Chat.Message.Preparations.SearchTerms
    end

    create :create do
      primary? true

      accept [
        :body,
        :client_message_id,
        :attachment_key,
        :attachment_filename,
        :attachment_content_type,
        :attachment_byte_size
      ]

      argument :room, :struct, allow_nil?: false, constraints: [instance_of: Campfire.Chat.Room]
      argument :deliver_webhooks?, :boolean, default: true

      change Changes.SetRoom
      change relate_actor(:creator)
      change Changes.EnsureClientMessageId
      validate Validations.HasContent
      change Changes.ResolveMentions
      change Changes.TouchRoomAndLoad
      change Changes.MarkUnread
      change Changes.NotifyCreated
    end

    update :update do
      primary? true
      # ResolveMentions reads the stored room_id and body, and needs the room's member list.
      require_atomic? false
      accept [:body]
      validate Validations.HasContent
      change Changes.ResolveMentions
      change Changes.TouchRoomAndLoad
      change {BroadcastAfterCommit, topic: :room, event: :message_updated}
    end

    destroy :destroy do
      primary? true
      change Changes.DeleteAttachment
      change {BroadcastAfterCommit, topic: :room, event: :message_deleted}
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(exists(room.memberships, user_id == ^actor(:id)))
    end

    policy action(:page) do
      # The inner read is filtered by room membership.
      authorize_if actor_present()
    end

    policy action(:create) do
      authorize_if Campfire.Checks.RoomMember
    end

    policy action([:update, :destroy]) do
      authorize_if expr(creator_id == ^actor(:id))
      authorize_if actor_attribute_equals(:role, :administrator)
    end
  end

  attributes do
    integer_primary_key :id

    attribute :body, :string do
      allow_nil? false
      default ""
      constraints allow_empty?: true
      public? true
    end

    attribute :client_message_id, :string do
      allow_nil? false
      public? true
    end

    attribute :mentioned_user_ids, {:array, :integer} do
      allow_nil? false
      default []
      public? true
    end

    attribute :attachment_key, :string, public?: true
    attribute :attachment_filename, :string, public?: true
    attribute :attachment_content_type, :string, public?: true
    attribute :attachment_byte_size, :integer, public?: true

    timestamps()
  end

  relationships do
    belongs_to :room, Campfire.Chat.Room do
      allow_nil? false
      attribute_type :integer
      public? true
    end

    belongs_to :creator, Campfire.Accounts.User do
      allow_nil? false
      attribute_type :integer
      public? true
    end

    has_many :boosts, Campfire.Chat.Boost do
      sort inserted_at: :asc, id: :asc
    end
  end

  calculations do
    calculate :plain_text, :string, fn records, _context ->
      Enum.map(records, &plain_text/1)
    end

    calculate :content_type, :atom, fn records, _context ->
      Enum.map(records, &content_type/1)
    end
  end

  @doc "The page size used by `page`."
  def page_size, do: @page_size

  @doc "What broadcasts and pages load on messages."
  def loads, do: @loads

  @doc "The body, else the attachment filename, else `\"\"`."
  def plain_text(%{body: body}) when is_binary(body) and body != "", do: body
  def plain_text(%{attachment_filename: name}) when is_binary(name), do: name
  def plain_text(_), do: ""

  @doc "`:attachment`, `:sound` (`/play <known sound>`) or `:text`."
  def content_type(%{attachment_key: key}) when is_binary(key), do: :attachment

  def content_type(message) do
    if sound_name(message), do: :sound, else: :text
  end

  @doc "The sound a `/play <name>` message plays, or nil."
  def sound_name(%{body: body}), do: Campfire.Sound.sound_name(body)
  def sound_name(_), do: nil

  @doc "Whether the message has an attachment."
  def attachment?(%{attachment_key: key}), do: is_binary(key)

  @doc """
  Deletes every message by the user, broadcasting each deletion (ban cleanup).
  """
  def remove_all_by_creator(user_id) do
    # System cleanup after a ban. Streaming runs the `:destroy` action per record, so each
    # message still deletes its attachment and broadcasts.
    __MODULE__
    |> Ash.Query.filter(creator_id == ^user_id)
    |> Ash.bulk_destroy!(:destroy, %{},
      authorize?: false,
      notify?: true,
      return_errors?: true,
      strategy: [:stream]
    )

    :ok
  end
end
