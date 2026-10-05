defmodule Campfire.Chat.Message.Preparations.SearchTerms do
  @moduledoc """
  Full-text search over the `search_vector` column: the last 100 matches, ascending, with
  creator and room loaded. A query with no word characters matches nothing.
  """

  use Ash.Resource.Preparation

  require Ash.Query

  @impl true
  def prepare(query, _opts, _context) do
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
end
