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
        {:ok, with_cursor(base, id, opts, &page_before(base, &1, opts))}

      id = args[:after] ->
        {:ok, with_cursor(base, id, opts, &page_after(base, &1, opts))}

      true ->
        {:ok, last_page(base, opts)}
    end
  end

  defp with_cursor(base, id, opts, fun) do
    case cursor(base, id, opts) do
      nil -> []
      message -> fun.(message)
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

  defp page_after(base, %{inserted_at: at, id: id}, opts) do
    base
    |> Ash.Query.filter(inserted_at > ^at or (inserted_at == ^at and id > ^id))
    |> Ash.Query.sort(inserted_at: :asc, id: :asc)
    |> Ash.Query.limit(Message.page_size())
    |> Ash.read!(opts)
  end
end
