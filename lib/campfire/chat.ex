defmodule Campfire.Chat do
  @moduledoc """
  Rooms, memberships, messages, boosts and recent searches.

  See docs/DOMAIN_API.md for the full list of functions.
  """

  use Ash.Domain, otp_app: :campfire

  require Ash.Query

  alias Campfire.Chat.{Boost, Membership, Message, Room, Search}

  resources do
    resource Room do
      define :list_rooms, action: :for_user
      define :get_room, action: :read, get_by: [:id]
      define :create_open_room, action: :create_open, args: [:name]
      define :create_closed_room, action: :create_closed, args: [:name, :user_ids]
      define :find_or_create_direct_room, action: :find_or_create_direct, args: [:user_ids]
      define :update_open_room, action: :update_open
      define :update_closed_room, action: :update_closed
      define :destroy_room, action: :destroy
    end

    resource Membership do
      define :list_memberships, action: :mine
      define :get_membership, action: :for_room, args: [:room_id], not_found_error?: false
      define :set_involvement, action: :set_involvement, args: [:involvement]
      define :mark_read, action: :mark_read
      define :revoke_membership, action: :revoke
    end

    resource Message do
      define :get_message, action: :read, get_by: [:id]
      define :page_messages, action: :page, args: [:room_id]
      define :search_messages, action: :search, args: [:query]
      define :create_message, action: :create, args: [:room]
      define :update_message, action: :update
      define :destroy_message, action: :destroy
    end

    resource Boost do
      define :get_boost, action: :read, get_by: [:id]
      define :create_boost, action: :create, args: [:message, :content]
      define :destroy_boost, action: :destroy
    end

    resource Search do
      define :record_search, action: :record, args: [:query]
      define :recent_searches, action: :recent
      define :clear_searches, action: :clear
    end
  end

  @doc """
  The number of messages in a room the actor can read (for the bot API's `X-Total-Count`).
  """
  def count_messages(room_id, opts) do
    Message
    |> Ash.Query.for_read(:read, %{}, Keyword.take(opts, [:actor, :authorize?, :tenant]))
    |> Ash.Query.filter(room_id == ^room_id)
    |> Ash.count()
  end
end
