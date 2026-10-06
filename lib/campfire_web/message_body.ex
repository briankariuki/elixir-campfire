defmodule CampfireWeb.MessageBody do
  @moduledoc """
  Renders a message's plain-text body as HTML (docs/PORTING.md §6, "Message rendering"). The body
  is parsed line by line into blocks, then rendered; everything is HTML-escaped, and the only tags
  that can appear are the ones this module emits, so no raw HTML passes through.

  ## Blocks

    * fenced code: a line of three backticks (optionally followed by a language), the code, and a
      closing line of three backticks, becomes `<pre><code>`. Nothing inside is formatted, linked
      or resolved as a mention. A fence that is never closed is plain text.
    * `> ` lines become a `<blockquote>`; a line right after a quote that starts with `— ` is the
      reply attribution and becomes `<cite>` (see "Replies"). Inside a quote, the other blocks
      (headings, lists, code) work too.
    * `# heading` becomes `<h1>` (the original only has a first-level heading).
    * `- item` / `* item` lines become a `<ul>`, `1. item` lines an `<ol>`.
    * everything else is text; newlines become `<br>`.

  ## Inline (within one line)

    * `**bold**`, `***bold italic***`, `*italic*` / `_italic_`, `~~strike~~`, `==highlight==`
      (`<mark>`) and `` `code` ``. A marker must hug the text (`* a*` is not italic) and `_` /
      single `*` don't apply inside a word (`snake_case_name`).
    * `http(s)://` URLs are linked (`target="_blank" rel="noopener"`), `@Name` mentions of the
      users in `mentioned_user_ids` are highlighted and linked to `/users/:id`. Both are taken out
      of the line before the formatting is applied, so neither is cut by a marker inside it, and
      neither happens inside inline code.

  The result is wrapped in `<div class="lexxy-content">`.

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

  # Never ends in a character that is probably a formatting marker (`**https://x.com**`), and stops
  # at the placeholder characters of `render_inline/2`
  @url_regex ~r|https?://[^\s<>"'\x{E000}\x{E001}]*[^\s<>"'.,;:!?)\]*_~\x{E000}\x{E001}]|u
  @quote_regex ~r/\A>(?: |\z)/
  # Emoji_Component also covers the digits, # and *, which emoji_only?/1 rejects separately
  @cite_prefix "— "
  @permalink_regex ~r{\A/rooms/\d+/@\d+\z}
  @emoji_regex ~r/\A(?:\p{Extended_Pictographic}|\p{Emoji_Component}|\x{FE0F}|\x{200D}|\s)+\z/u

  @fence_regex ~r/\A```([\w+#.-]{0,30})[ \t]*\z/u
  @heading_regex ~r/\A# +(\S.*)\z/u
  @bullet_regex ~r/\A[-*] +(\S.*)\z/u
  @number_regex ~r/\A(\d{1,9})\. +(\S.*)\z/u
  @code_span_regex ~r/`[^`\n]+`/u

  # Inline formatting, applied to escaped text in this order (`*` italic before bold, so that
  # `**a *b* c**` nests properly)
  @formats [
    {~r/\*\*\*(?=\S)(.+?)(?<=\S)\*\*\*/u, "<strong><em>\\1</em></strong>"},
    {~r/(?<![*\w])\*(?=[^\s*])(.+?)(?<=[^\s*])\*(?![*\w])/u, "<em>\\1</em>"},
    {~r/(?<!\w)_(?=[^\s_])(.+?)(?<=[^\s_])_(?!\w)/u, "<em>\\1</em>"},
    {~r/\*\*(?=\S)(.+?)(?<=\S)\*\*/u, "<strong>\\1</strong>"},
    {~r/~~(?=\S)(.+?)(?<=\S)~~/u, "<s>\\1</s>"},
    {~r/==(?=\S)(.+?)(?<=\S)==/u, "<mark>\\1</mark>"}
  ]

  # Code, URLs and mentions are swapped for `<E000>index<E001>` while the formatting is applied
  @slot_regex ~r/\x{E000}(\d+)\x{E001}/u

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
      |> parse(true)
      |> Enum.map(&elem(&1, 0))
      |> render_blocks(ctx)

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
    |> parse(true)
    |> Enum.reject(fn {block, _raw} -> elem(block, 0) in [:quote, :cite] end)
    |> Enum.flat_map(fn
      # no mentions are resolved in code
      {{:code, _, _}, raw} -> raw
      {_block, raw} -> Enum.map(raw, &strip_mentions(&1, mentioned))
    end)
    |> Enum.drop_while(&(String.trim(&1) == ""))
    |> Enum.reverse()
    |> Enum.drop_while(&(String.trim(&1) == ""))
    |> Enum.reverse()
    |> Enum.join("\n")
  end

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

  # The pre-filled attribution is followed by one blank line before the reply text.
  defp drop_blank_line(["" | rest]), do: rest
  defp drop_blank_line(lines), do: lines

  # Lines -> `[{block, raw_lines}]`, `raw_lines` being the lines the block was made of. Blocks:
  # `{:quote, lines}`, `{:cite, line}`, `{:code, language, lines}`, `{:heading, text}`,
  # `{:ul, items}`, `{:ol, {start, items}}` and `{:text, lines}`. `quotes?` is false inside a
  # quote: a nested quote is plain text, as in the original.
  defp parse([], _quotes?), do: []

  defp parse(lines, quotes?) do
    {entries, rest} = take_block(lines, quotes?)
    entries ++ parse(rest, quotes?)
  end

  defp take_block([line | rest] = lines, quotes?) do
    fence = take_fence(lines)

    cond do
      quotes? and quote_line?(line) ->
        {quoted, rest} = Enum.split_while(lines, &quote_line?/1)
        {cite, rest} = take_cite(rest)
        {[{{:quote, quoted}, quoted} | cite], rest}

      match?({:ok, _, _}, fence) ->
        {:ok, {language, code, raw}, rest} = fence
        {[{{:code, language, code}, raw}], rest}

      Regex.match?(@heading_regex, line) ->
        [_, text] = Regex.run(@heading_regex, line)
        {[{{:heading, text}, [line]}], rest}

      Regex.match?(@bullet_regex, line) ->
        {raw, rest} = Enum.split_while(lines, &Regex.match?(@bullet_regex, &1))
        items = Enum.map(raw, &(@bullet_regex |> Regex.run(&1) |> Enum.at(1)))
        {[{{:ul, items}, raw}], rest}

      Regex.match?(@number_regex, line) ->
        {raw, rest} = Enum.split_while(lines, &Regex.match?(@number_regex, &1))
        [{start, _} | _] = items = Enum.map(raw, &number_item/1)
        {[{{:ol, {start, Enum.map(items, &elem(&1, 1))}}, raw}], rest}

      true ->
        {text, rest} = take_text(rest, quotes?, [line])
        {[{{:text, text}, text}], rest}
    end
  end

  defp number_item(line) do
    [_, number, text] = Regex.run(@number_regex, line)
    {String.to_integer(number), text}
  end

  defp take_cite([line | rest] = lines) do
    if cite_line?(line),
      do: {[{{:cite, line}, [line]}], drop_blank_line(rest)},
      else: {[], lines}
  end

  defp take_cite([]), do: {[], []}

  # An opening fence with a closing one after it (an unclosed fence is plain text)
  defp take_fence([line | rest]) do
    with [_, language] <- Regex.run(@fence_regex, line),
         index when is_integer(index) <- Enum.find_index(rest, &closing_fence?/1) do
      {code, [closing | rest]} = Enum.split(rest, index)
      {:ok, {language, code, [line | code] ++ [closing]}, rest}
    else
      _ -> :error
    end
  end

  defp closing_fence?(line), do: String.trim(line) == "```"

  defp take_text([line | rest] = lines, quotes?, acc) do
    if block_start?(lines, quotes?),
      do: {Enum.reverse(acc), lines},
      else: take_text(rest, quotes?, [line | acc])
  end

  defp take_text([], _quotes?, acc), do: {Enum.reverse(acc), []}

  defp block_start?([line | _] = lines, quotes?) do
    (quotes? and quote_line?(line)) or Regex.match?(@heading_regex, line) or
      Regex.match?(@bullet_regex, line) or Regex.match?(@number_regex, line) or
      match?({:ok, _, _}, take_fence(lines))
  end

  # A block is a block: the blank line that only separates text from a heading, list or code block
  # would just add space
  defp render_blocks(blocks, ctx) do
    blocks
    |> tidy(nil)
    |> Enum.map(&render_block(&1, ctx))
  end

  defp tidy([], _previous), do: []

  defp tidy([{:text, lines} = block | rest], previous) do
    lines =
      lines
      |> maybe_drop_blank(structural?(previous), :first)
      |> maybe_drop_blank(structural?(List.first(rest)), :last)

    if lines == [],
      do: tidy(rest, block),
      else: [{:text, lines} | tidy(rest, block)]
  end

  defp tidy([block | rest], _previous), do: [block | tidy(rest, block)]

  defp structural?(block) when is_tuple(block), do: elem(block, 0) in [:code, :heading, :ul, :ol]
  defp structural?(_), do: false

  defp maybe_drop_blank(["" | rest], true, :first), do: rest

  defp maybe_drop_blank(lines, true, :last) do
    case Enum.reverse(lines) do
      ["" | rest] -> Enum.reverse(rest)
      _ -> lines
    end
  end

  defp maybe_drop_blank(lines, _structural?, _end), do: lines

  defp render_block({:text, lines}, ctx) do
    lines |> Enum.map(&render_inline(&1, ctx)) |> Enum.intersperse("<br>")
  end

  # A blockquote holds blocks too (lists, code) but no further quotes
  defp render_block({:quote, lines}, ctx) do
    inner =
      lines
      |> Enum.map(&Regex.replace(@quote_regex, &1, ""))
      |> parse(false)
      |> Enum.map(&elem(&1, 0))
      |> render_blocks(ctx)

    ["<blockquote>", inner, "</blockquote>"]
  end

  defp render_block({:cite, line}, ctx), do: render_cite(line, ctx)

  defp render_block({:heading, text}, ctx), do: ["<h1>", render_inline(text, ctx), "</h1>"]

  defp render_block({:ul, items}, ctx), do: ["<ul>", list_items(items, ctx), "</ul>"]

  defp render_block({:ol, {1, items}}, ctx), do: ["<ol>", list_items(items, ctx), "</ol>"]

  defp render_block({:ol, {start, items}}, ctx) do
    [~s(<ol start="#{start}">), list_items(items, ctx), "</ol>"]
  end

  defp render_block({:code, language, lines}, _ctx) do
    attr = if language == "", do: "", else: [~s( data-language="), escape(language), ~s(")]
    ["<pre", attr, "><code>", escape(Enum.join(lines, "\n")), "</code></pre>"]
  end

  defp list_items(items, ctx), do: Enum.map(items, &["<li>", render_inline(&1, ctx), "</li>"])

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

  ## Inline: code, links, mentions, formatting

  # 1. Code spans, URLs and mentions are replaced by placeholders (in that order, so code is never
  #    linked or resolved), 2. the rest is escaped and the formatting applied, 3. the placeholders
  #    are replaced by their HTML.
  defp render_inline(line, ctx) do
    {text, slots} =
      {String.replace(line, ~r/[\x{E000}\x{E001}]/u, ""), %{}}
      |> protect(@code_span_regex, &code_span/1)
      |> protect(@url_regex, &link/1)
      |> protect_mentions(ctx)

    text
    |> escape()
    |> format()
    |> restore(slots)
  end

  defp protect({text, slots}, regex, render) do
    {parts, slots} =
      regex
      |> Regex.split(text, include_captures: true)
      |> Enum.with_index()
      |> Enum.map_reduce(slots, fn
        {match, i}, slots when rem(i, 2) == 1 ->
          index = map_size(slots)
          {"\u{E000}#{index}\u{E001}", Map.put(slots, index, render.(match))}

        {text, _}, slots ->
          {text, slots}
      end)

    {Enum.join(parts), slots}
  end

  defp protect_mentions(acc, %{mentioned: mentioned} = ctx) do
    Enum.reduce(mentioned, acc, fn user, acc ->
      protect(acc, Mentions.mention_regex(user.name), fn _match -> mention(user, ctx) end)
    end)
  end

  defp format(html) do
    Enum.reduce(@formats, html, fn {regex, replacement}, html ->
      Regex.replace(regex, html, replacement)
    end)
  end

  defp restore(html, slots) when map_size(slots) == 0, do: html

  defp restore(html, slots) do
    Regex.replace(@slot_regex, html, fn _, index ->
      slots |> Map.fetch!(String.to_integer(index)) |> IO.iodata_to_binary()
    end)
  end

  defp code_span(match) do
    ["<code>", escape(String.slice(match, 1..-2//1)), "</code>"]
  end

  defp link(url) do
    escaped = escape(url)
    [~s(<a href="), escaped, ~s(" target="_blank" rel="noopener">), escaped, "</a>"]
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
