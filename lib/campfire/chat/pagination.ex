defmodule Campfire.Chat.Pagination do
  @moduledoc false
  # Implements Message's `:page` action: pages of 40 ordered by (inserted_at, id).

  require Ash.Query

  alias Campfire.Chat.Message

  def run(input, context) do
    args = input.arguments
    room_id = args.room_id

    # The actor, tenant and authorization flag live on the base query; every page is derived
    # from it, so the reads below can't forget them.
    base =
      Message
      |> Ash.Query.for_read(:read, %{}, Ash.Context.to_opts(context))
      |> Ash.Query.filter(room_id == ^room_id)
      |> Ash.Query.load(Message.loads())

    cond do
      id = args[:around] ->
        case cursor(base, id) do
          nil -> {:ok, last_page(base)}
          message -> {:ok, page_before(base, message) ++ [message] ++ page_after(base, message)}
        end

      id = args[:before] ->
        {:ok, page_before(base, cursor(base, id) || %{id: id})}

      id = args[:after] ->
        {:ok, page_after(base, cursor(base, id) || %{id: id})}

      true ->
        {:ok, last_page(base)}
    end
  end

  defp cursor(base, id) do
    base
    |> Ash.Query.filter(id == ^id)
    |> Ash.read_one!()
  end

  defp last_page(base) do
    base
    |> Ash.Query.sort(inserted_at: :desc, id: :desc)
    |> Ash.Query.limit(Message.page_size())
    |> Ash.read!()
    |> Enum.reverse()
  end

  defp page_before(base, %{inserted_at: at, id: id}) do
    base
    |> Ash.Query.filter(inserted_at < ^at or (inserted_at == ^at and id < ^id))
    |> Ash.Query.sort(inserted_at: :desc, id: :desc)
    |> Ash.Query.limit(Message.page_size())
    |> Ash.read!()
    |> Enum.reverse()
  end

  # The cursor message is gone (deleted, or not in this room): page by id instead
  defp page_before(base, %{id: id}) do
    base
    |> Ash.Query.filter(id < ^id)
    |> Ash.Query.sort(id: :desc)
    |> Ash.Query.limit(Message.page_size())
    |> Ash.read!()
    |> Enum.reverse()
  end

  defp page_after(base, %{inserted_at: at, id: id}) do
    base
    |> Ash.Query.filter(inserted_at > ^at or (inserted_at == ^at and id > ^id))
    |> Ash.Query.sort(inserted_at: :asc, id: :asc)
    |> Ash.Query.limit(Message.page_size())
    |> Ash.read!()
  end

  defp page_after(base, %{id: id}) do
    base
    |> Ash.Query.filter(id > ^id)
    |> Ash.Query.sort(id: :asc)
    |> Ash.Query.limit(Message.page_size())
    |> Ash.read!()
  end
end
