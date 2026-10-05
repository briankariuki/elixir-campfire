defmodule Campfire.Chat.Pagination do
  @moduledoc false
  # Implements Message's `:page` action: pages of 40 ordered by (inserted_at, id).

  require Ash.Query

  alias Campfire.Chat.{Message, MessageChanges}

  def run(input, context) do
    opts = Ash.Context.to_opts(context)
    args = input.arguments
    room_id = args.room_id

    base =
      Message
      |> Ash.Query.for_read(:read, %{}, opts)
      |> Ash.Query.filter(room_id == ^room_id)
      |> Ash.Query.load(MessageChanges.loads())

    cond do
      id = args[:around] ->
        case cursor(base, id, opts) do
          nil ->
            {:ok, last_page(base, opts)}

          message ->
            {:ok,
             page_before(base, message, opts) ++ [message] ++ page_after(base, message, opts)}
        end

      id = args[:before] ->
        {:ok, page_before(base, cursor(base, id, opts) || %{id: id}, opts)}

      id = args[:after] ->
        {:ok, page_after(base, cursor(base, id, opts) || %{id: id}, opts)}

      true ->
        {:ok, last_page(base, opts)}
    end
  end

  defp cursor(base, id, opts) do
    base
    |> Ash.Query.filter(id == ^id)
    |> Ash.read_one!(opts)
  end

  defp last_page(base, opts) do
    base
    |> Ash.Query.sort(inserted_at: :desc, id: :desc)
    |> Ash.Query.limit(Message.page_size())
    |> Ash.read!(opts)
    |> Enum.reverse()
  end

  defp page_before(base, %{inserted_at: at, id: id}, opts) do
    base
    |> Ash.Query.filter(inserted_at < ^at or (inserted_at == ^at and id < ^id))
    |> Ash.Query.sort(inserted_at: :desc, id: :desc)
    |> Ash.Query.limit(Message.page_size())
    |> Ash.read!(opts)
    |> Enum.reverse()
  end

  # The cursor message is gone (deleted, or not in this room): page by id instead
  defp page_before(base, %{id: id}, opts) do
    base
    |> Ash.Query.filter(id < ^id)
    |> Ash.Query.sort(id: :desc)
    |> Ash.Query.limit(Message.page_size())
    |> Ash.read!(opts)
    |> Enum.reverse()
  end

  defp page_after(base, %{inserted_at: at, id: id}, opts) do
    base
    |> Ash.Query.filter(inserted_at > ^at or (inserted_at == ^at and id > ^id))
    |> Ash.Query.sort(inserted_at: :asc, id: :asc)
    |> Ash.Query.limit(Message.page_size())
    |> Ash.read!(opts)
  end

  defp page_after(base, %{id: id}, opts) do
    base
    |> Ash.Query.filter(id > ^id)
    |> Ash.Query.sort(id: :asc)
    |> Ash.Query.limit(Message.page_size())
    |> Ash.read!(opts)
  end
end
