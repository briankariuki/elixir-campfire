defmodule CampfireWeb.MessageBody do
  @moduledoc """
  Renders a message's plain-text body as HTML (docs/PORTING.md §6, "Message rendering"):

  1. HTML-escape,
  2. autolink `http(s)://` URLs (`target="_blank" rel="noopener"`),
  3. turn `> ` lines into `<blockquote>`; a line right after a quote that starts with `— ` is the
     reply attribution and becomes `<cite>` (see "Replies"),
  4. highlight `@Name` mentions of the users in `mentioned_user_ids`, linked to `/users/:id`,
  5. turn newlines into `<br>`,
  6. wrap everything in `<div class="lexxy-content">`.

  ## Replies

  The Reply action pre-fills the composer with `reply_text/2`:

      > quoted line
      — Author /rooms/1/@123

  Rendered, that is `<blockquote>quoted line</blockquote><cite>Author <a href="/rooms/1/@123">#</a></cite>`
  (the original Campfire's markup; `actiontext.css` adds the "— " before a `cite`). Only a trailing
  same-site message permalink (a path, or a URL on this endpoint's host) becomes the `#` link; any
  other `— text` line is a plain, escaped `<cite>`.

  ## Live navigation

  Mention and `#` links are plain links by default (bot API JSON, webhooks). Pass `live: true` inside
  a LiveView to add the attributes `<.link navigate>` renders (`data-phx-link="redirect"`,
  `data-phx-link-state="push"`), so they navigate without a full page load.
  """

  alias Campfire.Chat.Mentions
  alias Campfire.Chat.Message
  alias CampfireWeb.{Endpoint, Paths}

  @url_regex ~r{https?://[^\s<>"']*[^\s<>"'.,;:!?)\]]}u
  @quote_regex ~r/\A>(?: |\z)/
  # Emoji_Component also covers the digits, # and *, which emoji_only?/1 rejects separately
  @cite_prefix "— "
  @permalink_regex ~r{\A/rooms/\d+/@\d+\z}
  @emoji_regex ~r/\A(?:\p{Extended_Pictographic}|\p{Emoji_Component}|\x{FE0F}|\x{200D}|\s)+\z/u

  @doc """
  Returns the body as `Phoenix.HTML.safe()`.

  `users` is an optional `%{id => %User{}}` map used to resolve mentions; mentioned users missing
  from it are loaded from the database. Options: `live: true` (see the moduledoc).
  """
  def to_html(message, users \\ %{}, opts \\ []) do
    ctx = %{mentioned: mentioned_users(message, users), live?: Keyword.get(opts, :live, false)}

    html =
      (message.body || "")
      |> split_lines()
      |> Enum.chunk_by(&quote_line?/1)
      |> render_chunks(ctx, false)

    {:safe, [~s(<div class="lexxy-content">), html, "</div>"]}
  end

  @doc """
  The body as an HTML string, or `""` for a message without a text body (an attachment). This is the
  `body.html` of the bot API and of webhook payloads.
  """
  def to_html_string(message, users \\ %{}, opts \\ [])

  def to_html_string(%{body: body} = message, users, opts) when is_binary(body) and body != "" do
    message |> to_html(users, opts) |> Phoenix.HTML.safe_to_string()
  end

  def to_html_string(_message, _users, _opts), do: ""

  @doc """
  The text the Reply action pre-fills the composer with: the message quoted line by line, then the
  attribution, then a blank line to type the reply on:

      > quoted
      — Author /rooms/1/@123

  `message` needs `:creator` loaded. As in the original, nested quotes, an earlier reply's
  attribution and mentions (the `@` is dropped, so the reply doesn't notify anyone again) are not
  carried over. A `/play` message quotes the sound's caption (its text, or `🔊 name` for the image
  sounds), since that is what the message shows.
  """
  def reply_text(message, users \\ %{}) do
    quoted =
      message
      |> quotable_text(users)
      |> split_lines()
      |> Enum.map_join("\n", &String.trim_trailing("> " <> &1))

    "#{quoted}\n#{@cite_prefix}#{one_line(message.creator.name)} #{Paths.message_path(message)}\n\n"
  end

  defp quotable_text(message, users) do
    case sound_caption(message) do
      nil -> text_quote(message, users)
      caption -> caption
    end
  end

  defp sound_caption(message) do
    with name when is_binary(name) <- Message.sound_name(message) do
      case Campfire.Sound.find(name) do
        {:text, text} -> String.trim(text)
        _image -> "🔊 " <> name
      end
    end
  end

  defp text_quote(message, users) do
    mentioned = mentioned_users(message, users)

    (message.body || "")
    |> split_lines()
    |> Enum.chunk_by(&quote_line?/1)
    |> drop_quotes_and_cites(false)
    |> Enum.map(&strip_mentions(&1, mentioned))
    |> Enum.drop_while(&(String.trim(&1) == ""))
    |> Enum.reverse()
    |> Enum.drop_while(&(String.trim(&1) == ""))
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  defp drop_quotes_and_cites([], _after_quote?), do: []

  defp drop_quotes_and_cites([[first | _] = chunk | rest], after_quote?) do
    cond do
      quote_line?(first) -> drop_quotes_and_cites(rest, true)
      after_quote? -> drop_cite(chunk) ++ drop_quotes_and_cites(rest, false)
      true -> chunk ++ drop_quotes_and_cites(rest, false)
    end
  end

  defp drop_cite([line | rest] = lines) do
    if cite_line?(line), do: drop_blank_line(rest), else: lines
  end

  # The pre-filled attribution is followed by one blank line before the reply text.
  defp drop_blank_line(["" | rest]), do: rest
  defp drop_blank_line(lines), do: lines

  defp strip_mentions(line, mentioned) do
    Enum.reduce(mentioned, line, fn user, line ->
      Regex.replace(Mentions.mention_regex(user.name), line, fn _, _ -> user.name end)
    end)
  end

  defp one_line(text), do: text |> String.split(~r/\s+/, trim: true) |> Enum.join(" ")

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
        missing
        |> Campfire.Accounts.list_users_by_ids!()
        |> Map.new(&{&1.id, &1})
      end

    ids
    |> Enum.map(&(Map.get(users, &1) || Map.get(loaded, &1)))
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(&String.length(&1.name), :desc)
  end

  defp mentioned_users(_message, _users), do: []

  ## Blocks

  defp split_lines(text), do: String.split(text, ~r/\r?\n/)

  defp quote_line?(line), do: Regex.match?(@quote_regex, line)

  defp cite_line?(line), do: String.starts_with?(line, @cite_prefix)

  # `chunks` alternate between quotes and text, and a blockquote is a block, so the chunks need no
  # <br> between them. `after_quote?` says the previous chunk was a quote: the first line of a text
  # chunk may then be its attribution.
  defp render_chunks([], _ctx, _after_quote?), do: []

  defp render_chunks([[first | _] = lines | rest], ctx, after_quote?) do
    if quote_line?(first) do
      inner =
        lines
        |> Enum.map(&render_inline(Regex.replace(@quote_regex, &1, ""), ctx))
        |> Enum.intersperse("<br>")

      ["<blockquote>", inner, "</blockquote>" | render_chunks(rest, ctx, true)]
    else
      [render_text_lines(lines, ctx, after_quote?) | render_chunks(rest, ctx, false)]
    end
  end

  defp render_text_lines([line | rest] = lines, ctx, true) do
    if cite_line?(line) do
      # <cite> is a block: no <br> after it, and the blank line that separates the attribution
      # from the reply text would only add space.
      [render_cite(line, ctx) | rest |> drop_blank_line() |> render_text_lines(ctx, false)]
    else
      render_text_lines(lines, ctx, false)
    end
  end

  defp render_text_lines(lines, ctx, false) do
    lines |> Enum.map(&render_inline(&1, ctx)) |> Enum.intersperse("<br>")
  end

  # `— Author /rooms/1/@123` -> `<cite>Author <a href="/rooms/1/@123">#</a></cite>`. Without a
  # same-site permalink at the end, the whole text is the (escaped) citation.
  defp render_cite(line, ctx) do
    text = String.replace_prefix(line, @cite_prefix, "")

    with [_, author, token] <- Regex.run(~r/\A(.*?)\s*(\S+)\z/su, text),
         {:ok, path} <- permalink_path(token) do
      ["<cite>", escape(String.trim_trailing(author)), " ", permalink_link(path, ctx), "</cite>"]
    else
      _ -> ["<cite>", escape(String.trim(text)), "</cite>"]
    end
  end

  # Only the site's own message permalinks, as a path or as a URL on this endpoint's host.
  defp permalink_path(token) do
    path = String.replace_prefix(token, Endpoint.url(), "")

    if Regex.match?(@permalink_regex, path), do: {:ok, path}, else: :error
  end

  defp permalink_link(path, ctx) do
    [~s(<a href="), escape(path), ~s("), live_attrs(ctx), ">#</a>"]
  end

  defp live_attrs(%{live?: true}), do: ~s( data-phx-link="redirect" data-phx-link-state="push")
  defp live_attrs(_ctx), do: ""

  ## Inline: links, mentions, text

  defp render_inline(line, ctx) do
    @url_regex
    |> Regex.split(line, include_captures: true)
    |> Enum.with_index()
    |> Enum.map(fn
      {url, i} when rem(i, 2) == 1 -> link(url)
      {text, _} -> render_text(text, ctx)
    end)
  end

  defp link(url) do
    escaped = escape(url)
    [~s(<a href="), escaped, ~s(" target="_blank" rel="noopener">), escaped, "</a>"]
  end

  defp render_text(text, %{mentioned: mentioned} = ctx) do
    mentioned
    |> Enum.reduce([text], fn user, segments ->
      Enum.flat_map(segments, &split_mention(&1, user))
    end)
    |> Enum.map(fn
      {:mention, user} -> mention(user, ctx)
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

  # The original's `users/_mention`: the avatar links to the profile, the name follows.
  defp mention(user, ctx) do
    [
      ~s(<span class="mention"><a class="btn avatar" href="),
      escape("/users/#{user.id}"),
      ~s(" title="),
      escape(user.name),
      ~s("),
      live_attrs(ctx),
      ~s(><img src="),
      escape(Paths.avatar_path(user)),
      ~s(" alt="" aria-hidden="true"></a> ),
      escape(user.name),
      "</span>"
    ]
  end

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
