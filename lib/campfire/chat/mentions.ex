defmodule Campfire.Chat.Mentions do
  @moduledoc """
  `@Full Name` mentions in message bodies.

  A mention is `@` followed by a room member's exact name, not followed by another letter, digit
  or underscore. Longer names are matched first, so `@Ann Smith` wins over `@Ann`.
  """

  import Ecto.Query

  alias Campfire.Repo

  @doc """
  The ids of the `members` (`{id, name}` tuples or maps with `:id` and `:name`) mentioned in
  `body`.
  """
  @spec mentioned_ids(String.t() | nil, [{integer(), String.t()} | map()]) :: [integer()]
  def mentioned_ids(body, members) when is_binary(body) and body != "" do
    members
    |> Enum.map(fn
      {id, name} -> {id, name}
      %{id: id, name: name} -> {id, name}
    end)
    |> Enum.reject(fn {_id, name} -> name in [nil, ""] end)
    |> Enum.sort_by(fn {_id, name} -> String.length(name) end, :desc)
    |> Enum.reduce({body, []}, fn {id, name}, {text, ids} ->
      regex = mention_regex(name)

      if Regex.match?(regex, text) do
        {Regex.replace(regex, text, ""), [id | ids]}
      else
        {text, ids}
      end
    end)
    |> elem(1)
    |> Enum.reverse()
    |> Enum.uniq()
  end

  def mentioned_ids(_body, _members), do: []

  @doc "A regex matching `@name` as a whole mention."
  def mention_regex(name) do
    Regex.compile!("@" <> Regex.escape(name) <> "(?![\\p{L}\\p{N}_])", "u")
  end

  @doc "The `{id, name}` of every member of the room."
  def room_members(room_id) do
    Repo.all(
      from u in "users",
        join: m in "memberships",
        on: m.user_id == u.id,
        where: m.room_id == ^room_id,
        select: {u.id, u.name}
    )
  end
end
