defmodule Campfire.Chat.Pagination do
  @moduledoc false
  # Implements Message's `:page` action: pages of 40 ordered by (inserted_at, id).
  #
  # Every read goes through `Message`'s keyset-paginated `:in_room` action (so the read policy
  # applies), except the last page (`:latest_in_room`: Ash keyset has no "last", so it reads the
  # newest 40 descending and reverses them). A cursor message id is turned into a keyset by reading
  # that message through `:in_room`; `page: [before: keyset]` still returns ascending results.

  require Ash.Query

  alias Campfire.Chat.Message

  def run(input, context) do
    args = input.arguments
    opts = Ash.Context.to_opts(context)
    room_id = args.room_id

    cond do
      id = args[:around] ->
        case cursor(room_id, id, opts) do
          nil ->
            {:ok, last_page(room_id, opts)}

          message ->
            {:ok,
             page_before(room_id, message, opts) ++
               [message] ++ page_after(room_id, message, opts)}
        end

      id = args[:before] ->
        {:ok, page_before(room_id, cursor(room_id, id, opts) || %{id: id}, opts)}

      id = args[:after] ->
        {:ok, page_after(room_id, cursor(room_id, id, opts) || %{id: id}, opts)}

      true ->
        {:ok, last_page(room_id, opts)}
    end
  end

  # The cursor message with its `:keyset` metadata, or nil when it is gone or not in this room.
  defp cursor(room_id, id, opts) do
    room_id
    |> in_room(opts)
    |> Ash.Query.filter(id == ^id)
    |> Ash.read!(page: [limit: 1])
    |> Map.fetch!(:results)
    |> List.first()
  end

  defp last_page(room_id, opts) do
    Message
    |> Ash.Query.for_read(:latest_in_room, %{room_id: room_id}, opts)
    |> Ash.read!()
    |> Enum.reverse()
  end

  defp page_before(room_id, %Message{} = message, opts),
    do: keyset_page(room_id, [before: keyset(message)], opts)

  # The cursor message is gone (deleted, or not in this room): page by id instead
  defp page_before(room_id, %{id: id}, opts) do
    room_id
    |> in_room(opts)
    |> Ash.Query.unset(:sort)
    |> Ash.Query.filter(id < ^id)
    |> Ash.Query.sort(id: :desc)
    |> Ash.Query.limit(Message.page_size())
    |> Ash.read!()
    |> Enum.reverse()
  end

  defp page_after(room_id, %Message{} = message, opts),
    do: keyset_page(room_id, [after: keyset(message)], opts)

  defp page_after(room_id, %{id: id}, opts) do
    room_id
    |> in_room(opts)
    |> Ash.Query.unset(:sort)
    |> Ash.Query.filter(id > ^id)
    |> Ash.Query.sort(id: :asc)
    |> Ash.Query.limit(Message.page_size())
    |> Ash.read!()
  end

  defp keyset(message), do: Ash.Resource.get_metadata(message, :keyset)

  defp keyset_page(room_id, cursor, opts) do
    room_id
    |> in_room(opts)
    |> Ash.read!(page: [limit: Message.page_size()] ++ cursor)
    |> Map.fetch!(:results)
  end

  # `opts` carries the actor, tenant and authorization flag of the `:page` call.
  defp in_room(room_id, opts),
    do: Ash.Query.for_read(Message, :in_room, %{room_id: room_id}, opts)
end
