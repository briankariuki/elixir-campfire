defmodule CampfireWeb.MessageBody do
  @moduledoc """
  Renders a message's plain-text body as HTML (docs/PORTING.md §6, "Message rendering"):

  1. HTML-escape,
  2. autolink `http(s)://` URLs (`target="_blank" rel="noopener"`),
  3. turn `> ` lines into `<blockquote>`,
  4. highlight `@Name` mentions of the users in `mentioned_user_ids`,
  5. turn newlines into `<br>`,
  6. wrap everything in `<div class="lexxy-content">`.
  """

  alias Campfire.Chat.Mentions
  alias CampfireWeb.Paths

  @url_regex ~r{https?://[^\s<>"']*[^\s<>"'.,;:!?)\]]}u
  @quote_regex ~r/\A>(?: |\z)/
  # Emoji_Component also covers the digits, # and *, which emoji_only?/1 rejects separately
  @emoji_regex ~r/\A(?:\p{Extended_Pictographic}|\p{Emoji_Component}|\x{FE0F}|\x{200D}|\s)+\z/u

  @doc """
  Returns the body as `Phoenix.HTML.safe()`.

  `users` is an optional `%{id => %User{}}` map used to resolve mentions; mentioned users missing
  from it are loaded from the database.
  """
  def to_html(message, users \\ %{}) do
    mentioned = mentioned_users(message, users)

    html =
      (message.body || "")
      |> String.split(~r/\r?\n/)
      |> Enum.chunk_by(&quote_line?/1)
      # Adjacent chunks alternate between quotes and text, and a blockquote is a block, so the
      # chunks need no <br> between them.
      |> Enum.map(&render_chunk(&1, mentioned))

    {:safe, [~s(<div class="lexxy-content">), html, "</div>"]}
  end

  @doc "Whether the text consists only of emoji (and whitespace)."
  def emoji_only?(text) when is_binary(text) do
    String.trim(text) != "" and Regex.match?(@emoji_regex, text) and
      not Regex.match?(~r/[0-9#*]/, text)
  end

  def emoji_only?(_), do: false

  ## Mentions

  defp mentioned_users(%{mentioned_user_ids: ids}, users) when is_list(ids) and ids != [] do
    missing = Enum.reject(ids, &Map.has_key?(users, &1))

    loaded =
      if missing == [] do
        %{}
      else
        # Rendering has no actor (bot JSON, components); the message is already visible to the
        # viewer, and mentions only need the users' names.
        missing
        |> Campfire.Accounts.list_users_by_ids!(authorize?: false)
        |> Map.new(&{&1.id, &1})
      end

    ids
    |> Enum.map(&(Map.get(users, &1) || Map.get(loaded, &1)))
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(&String.length(&1.name), :desc)
  end

  defp mentioned_users(_message, _users), do: []

  ## Blocks

  defp quote_line?(line), do: Regex.match?(@quote_regex, line)

  defp render_chunk([first | _] = lines, mentioned) do
    if quote_line?(first) do
      inner =
        lines
        |> Enum.map(&render_inline(Regex.replace(@quote_regex, &1, ""), mentioned))
        |> Enum.intersperse("<br>")

      ["<blockquote>", inner, "</blockquote>"]
    else
      lines |> Enum.map(&render_inline(&1, mentioned)) |> Enum.intersperse("<br>")
    end
  end

  ## Inline: links, mentions, text

  defp render_inline(line, mentioned) do
    @url_regex
    |> Regex.split(line, include_captures: true)
    |> Enum.with_index()
    |> Enum.map(fn
      {url, i} when rem(i, 2) == 1 -> link(url)
      {text, _} -> render_text(text, mentioned)
    end)
  end

  defp link(url) do
    escaped = escape(url)
    [~s(<a href="), escaped, ~s(" target="_blank" rel="noopener">), escaped, "</a>"]
  end

  defp render_text(text, mentioned) do
    mentioned
    |> Enum.reduce([text], fn user, segments ->
      Enum.flat_map(segments, &split_mention(&1, user))
    end)
    |> Enum.map(fn
      {:mention, user} -> mention(user)
      text -> escape(text)
    end)
  end

  defp split_mention({:mention, _} = mention, _user), do: [mention]

  defp split_mention(text, user) do
    user.name
    |> Mentions.mention_regex()
    |> Regex.split(text, include_captures: true)
    |> Enum.with_index()
    |> Enum.map(fn
      {_match, i} when rem(i, 2) == 1 -> {:mention, user}
      {text, _} -> text
    end)
  end

  defp mention(user) do
    [
      ~s(<span class="mention"><img class="avatar" src="),
      escape(Paths.avatar_path(user)),
      ~s(" alt="" aria-hidden="true"> ),
      escape(user.name),
      "</span>"
    ]
  end

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
