defmodule Campfire.Chat.Mentions do
  @moduledoc """
  `@Full Name` mentions in message bodies.

  A mention is `@` followed by a room member's exact name, neither preceded nor followed by a
  letter, digit or underscore (so `ops@Deploy.example` doesn't mention "Deploy"). Longer names are
  matched first, so `@Ann Smith` wins over `@Ann`. Members sharing a name are all mentioned.
  """

  require Ash.Query

  alias Campfire.Chat.Membership

  @doc """
  The ids of the `members` (`{id, name}` tuples or maps with `:id` and `:name`) mentioned in
  `body`.
  """
  @spec mentioned_ids(String.t() | nil, [{integer(), String.t()} | map()]) :: [integer()]
  def mentioned_ids(body, members) when is_binary(body) and body != "" do
    pairs =
      members
      |> Enum.map(fn
        {id, name} -> {id, name}
        %{id: id, name: name} -> {id, name}
      end)
      |> Enum.reject(fn {_id, name} -> name in [nil, ""] end)

    ids_by_name = Enum.group_by(pairs, fn {_id, name} -> name end, fn {id, _name} -> id end)

    pairs
    |> Enum.map(fn {_id, name} -> name end)
    |> Enum.uniq()
    |> Enum.sort_by(&String.length/1, :desc)
    |> Enum.reduce({body, []}, fn name, {text, ids} ->
      regex = mention_regex(name)

      if Regex.match?(regex, text) do
        {Regex.replace(regex, text, ""), Enum.reverse(Map.fetch!(ids_by_name, name), ids)}
      else
        {text, ids}
      end
    end)
    |> elem(1)
    |> Enum.reverse()
    |> Enum.uniq()
  end

  def mentioned_ids(_body, _members), do: []

  @doc """
  A regex matching `@name` as a whole mention: the `@` must not follow a letter, digit or `_`
  (e.g. in an email address) and the name must not be followed by one. Both checks are zero-width,
  so the match is exactly `@name`.
  """
  def mention_regex(name) do
    Regex.compile!("(?<![\\p{L}\\p{N}_])@" <> Regex.escape(name) <> "(?![\\p{L}\\p{N}_])", "u")
  end

  @doc "The `{id, name}` of every member of the room."
  def room_members(room_id) do
    # Internal lookup while saving a message (the author may only see their own memberships).
    Membership
    |> Ash.Query.filter(room_id == ^room_id)
    |> Ash.Query.select([:user_id])
    |> Ash.Query.load(user: [:name])
    |> Ash.read!(authorize?: false)
    |> Enum.map(&{&1.user_id, &1.user.name})
  end
end
