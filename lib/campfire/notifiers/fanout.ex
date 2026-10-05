defmodule Campfire.Notifiers.Fanout do
  @moduledoc """
  The notifications that go to a computed set of users, which a topic template on
  `Ash.Notifier.PubSub` can't express. Like every notifier it runs after the outermost
  transaction commits, and sends the messages of docs/PORTING.md §4:

    * `Message` create: `{:room_unread, room_id}` to every member of the room, and bot
      webhook jobs (unless the `:deliver_webhooks?` argument is false)
    * `Room` create/update: `:sidebar_changed` to the current members (users revoked by
      `ReviseMembers` are told by `Membership`'s own publications)
    * `Room` destroy: `{:room_removed, id}` and `:sidebar_changed` to the members captured
      before the delete (`:room_contents` in the changeset context, see `DestroyContents`)
  """

  use Ash.Notifier

  alias Ash.Notifier.Notification
  alias Campfire.Broadcast
  alias Campfire.Chat.{Membership, Message, Room}

  @impl true
  def notify(%Notification{resource: Message, action: %{type: :create}} = notification) do
    message = notification.data

    Broadcast.users(Membership.member_ids(message.room_id), {:room_unread, message.room_id})

    if Ash.Changeset.get_argument(notification.changeset, :deliver_webhooks?) != false do
      room = Ash.Changeset.get_argument(notification.changeset, :room)
      Campfire.Webhooks.enqueue_for_message(message, room)
    end

    :ok
  end

  def notify(%Notification{resource: Room, action: %{type: type}, data: room})
      when type in [:create, :update] do
    Broadcast.users(Membership.member_ids(room.id), :sidebar_changed)
    :ok
  end

  def notify(%Notification{resource: Room, action: %{type: :destroy}, data: room} = notification) do
    %{member_ids: member_ids} = notification.changeset.context.room_contents
    Broadcast.users(member_ids, {:room_removed, room.id})
    Broadcast.users(member_ids, :sidebar_changed)
    :ok
  end
end
