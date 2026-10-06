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
    * `- item` / `* item` lines become a `<ul>`, `1. item` lines an `<ol>`. An item indented under
      another one (2 or more spaces, or a tab, per level) starts a list inside that item's `<li>`;
      bullets and numbers mix freely. Up to 4 levels: deeper indentation stays on the last one. A list
      always starts on an unindented item, and a line indented by a single space is text.
    * everything else is text; newlines become `<br>`.

  ## Inline (within one line)

    * `**bold**`, `***bold italic***`, `*italic*` / `_italic_`, `~~strike~~`, `==highlight==`
      (`<mark>`) and `` `code` ``. A marker must hug the text (`* a*` is not italic) and `_` /
      single `*` don't apply inside a word (`snake_case_name`).
    * `[text](https://url)` becomes a link (`target="_blank" rel="noopener"`). The URL must be
      absolute `http(s)://` with a host and contain no spaces; it may hold balanced parentheses
      (`https://en.wikipedia.org/wiki/Elixir_(programming_language)`), so a `)` after the closing
      one is the surrounding text's. Anything else (`javascript:`, `data:`, relative, a missing
      `)`, empty text) stays literal, escaped text. The text can be formatted (bold, code, ...) but
      holds no links, URLs or mentions of its own.
    * `http(s)://` URLs are linked (`target="_blank" rel="noopener"`), `@Name` mentions of the
      users in `mentioned_user_ids` are highlighted and linked to `/users/:id`. Both are taken out
      of the line before the formatting is applied, so neither is cut by a marker inside it, and
      neither happens inside inline code.

  The result is wrapped in `<div class="lexxy-content">`.

  ## Replies

  The Reply action pre-fills the composer with `reply_text/2`:

      > quoted line
      — Author /rooms/1/@123

  The quote is the message's source text, so links, lists and the rest are quoted as typed.
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
  alias CampfireWeb.MessageBody.Cache
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
  @code_span_regex ~r/`[^`\n]+`/u
  # A list item: indentation, `-`/`*` or `N.`, the text. Only unindented ones start a list.
  @list_item_regex ~r/\A([ \t]*)(?:([-*])|(\d{1,9})\.) +(\S.*)\z/u
  @max_list_depth 4

  # `[text](url)`, the text without brackets and with something in it, the url absolute http(s) with
  # a host and no spaces; parentheses in it come in balanced pairs (one level), so the first
  # unbalanced `)` closes the link. Code spans and mentions are placeholders by then (the
  # placeholder characters are excluded from the url, text can hold them).
  @markdown_link_regex ~r|\[(?=[^\[\]\n]*\S)([^\[\]\n]+)\]\((https?://[^\s()<>"/?#\x{E000}\x{E001}][^\s()<>"\x{E000}\x{E001}]*(?:\([^\s()<>"\x{E000}\x{E001}]*\)[^\s()<>"\x{E000}\x{E001}]*)*)\)|u

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
  `to_html/3`, rendered once per message version and kept in `CampfireWeb.MessageBody.Cache`, for
  the room and search LiveViews, where every connected viewer renders the same message.

  Returns `{:safe, binary}`. The key is the message id and `updated_at`, the `live` option, and a
  hash of the body and of the mentioned users' id, name and avatar key (what the mention markup
  shows), so an edit or a rename renders again. Messages without an id or a text body are rendered
  uncached.
  """
  def cached_html(message, users \\ %{}, opts \\ [])

  def cached_html(%{id: id, body: body} = message, users, opts)
      when not is_nil(id) and is_binary(body) and body != "" do
    mentioned = mentioned_users(message, users)
    live? = Keyword.get(opts, :live, false)
    key = {id, Map.get(message, :updated_at), live?, digest(body, mentioned)}

    html =
      Cache.fetch(key, fn ->
        # The mentioned users are resolved already, so a miss doesn't load them again
        message |> to_html(Map.new(mentioned, &{&1.id, &1}), opts) |> safe_binary()
      end)

    {:safe, html}
  end

  def cached_html(message, users, opts), do: to_html(message, users, opts)

  defp safe_binary({:safe, iodata}), do: IO.iodata_to_binary(iodata)

  # What the output depends on besides the message version: the body and the mention markup
  defp digest(body, mentioned) do
    users = Enum.map(mentioned, &{&1.id, &1.name, &1.avatar_key})
    :erlang.md5(:erlang.term_to_binary({body, users}))
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
  # `{:lists, [list]}` (see `parse_lists/1`) and `{:text, lines}`. `quotes?` is false inside a
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

      list_start?(line) ->
        {raw, rest} = Enum.split_while(lines, &(list_item(&1) != nil))
        {[{{:lists, parse_lists(raw)}, raw}], rest}

      true ->
        {text, rest} = take_text(rest, quotes?, [line])
        {[{{:text, text}, text}], rest}
    end
  end

  # `{width, kind, number, text}` for a list item line, else nil. `kind` is `:ul` or `:ol` (with
  # its number); a tab counts as two spaces. An indent of a single space is no indent at all, so
  # " - x" isn't an item.
  defp list_item(line) do
    case Regex.run(@list_item_regex, line) do
      [_, indent, _bullet, "", text] -> item(indent, :ul, nil, text)
      [_, indent, "", number, text] -> item(indent, :ol, String.to_integer(number), text)
      _ -> nil
    end
  end

  defp item(indent, kind, number, text) do
    case indent_width(indent) do
      1 -> nil
      width -> {width, kind, number, text}
    end
  end

  defp indent_width(indent) do
    indent |> String.to_charlist() |> Enum.reduce(0, &(&2 + if(&1 == ?\t, do: 2, else: 1)))
  end

  defp list_start?(line), do: match?({0, _, _, _}, list_item(line))

  # Item lines (the first one unindented) -> `[{:list, kind, start, items}]`, `items` being
  # `[{text, nested_lists}]`. A list is the consecutive items of one kind at one level; another
  # kind starts a new list right after it.
  defp parse_lists(lines) do
    {lists, []} =
      lines
      |> Enum.map(&list_item/1)
      |> assign_levels()
      |> build_lists(0)

    lists
  end

  # `[{width, kind, number, text}]` -> `[{level, kind, number, text}]`. An item at least two wider
  # than the previous one is a level deeper (at most @max_list_depth levels); a narrower one goes
  # back to the level of that indentation (or the nearest deeper one).
  defp assign_levels(items) do
    {leveled, _stack} =
      Enum.map_reduce(items, [], fn {width, kind, number, text}, stack ->
        stack = next_levels(stack, width)
        {{length(stack) - 1, kind, number, text}, stack}
      end)

    leveled
  end

  # The stack holds the widths of the open levels, the innermost first
  defp next_levels([], width), do: [width]

  defp next_levels([top | _] = stack, width) when width >= top + 2 do
    if length(stack) < @max_list_depth, do: [width | stack], else: stack
  end

  # Narrower: back out to that level, or when it falls between two levels, to the deeper one
  defp next_levels(stack, width) do
    case Enum.split_while(stack, &(&1 > width)) do
      {[], stack} -> stack
      {_popped, [^width | _] = outer} -> outer
      {popped, outer} -> [List.last(popped) | outer]
    end
  end

  defp build_lists([{level, kind, number, _} | _] = items, level) do
    {list_items, rest} = take_list_items(items, level, kind, [])
    {more, rest} = build_lists(rest, level)
    {[{:list, kind, number, list_items} | more], rest}
  end

  defp build_lists(items, _level), do: {[], items}

  defp take_list_items([{level, kind, _, text} | rest], level, kind, acc) do
    {children, rest} = build_lists(rest, level + 1)
    take_list_items(rest, level, kind, [{text, children} | acc])
  end

  defp take_list_items(items, _level, _kind, acc), do: {Enum.reverse(acc), items}

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
      list_start?(line) or match?({:ok, _, _}, take_fence(lines))
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

  defp structural?(block) when is_tuple(block), do: elem(block, 0) in [:code, :heading, :lists]
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

  defp render_block({:lists, lists}, ctx), do: Enum.map(lists, &render_list(&1, ctx))

  defp render_block({:code, language, lines}, _ctx) do
    attr = if language == "", do: "", else: [~s( data-language="), escape(language), ~s(")]
    ["<pre", attr, "><code>", escape(Enum.join(lines, "\n")), "</code></pre>"]
  end

  defp render_list({:list, :ul, _, items}, ctx), do: ["<ul>", list_items(items, ctx), "</ul>"]
  defp render_list({:list, :ol, 1, items}, ctx), do: ["<ol>", list_items(items, ctx), "</ol>"]

  defp render_list({:list, :ol, start, items}, ctx) do
    [~s(<ol start="#{start}">), list_items(items, ctx), "</ol>"]
  end

  defp list_items(items, ctx) do
    Enum.map(items, fn {text, nested} ->
      ["<li>", render_inline(text, ctx), Enum.map(nested, &render_list(&1, ctx)), "</li>"]
    end)
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

  ## Inline: code, links, mentions, formatting

  # 1. Code spans, `[text](url)` links, bare URLs and mentions are replaced by placeholders (in that
  #    order, so code is never linked or resolved and a URL inside a link isn't linked again),
  #    2. the rest is escaped and the formatting applied, 3. the placeholders are replaced by their
  #    HTML.
  defp render_inline(line, ctx) do
    {text, slots} =
      {String.replace(line, ~r/[\x{E000}\x{E001}]/u, ""), %{}}
      |> protect(@code_span_regex, fn match, _slots -> code_span(match) end)
      |> protect(@markdown_link_regex, &markdown_link/2)
      |> protect(@url_regex, fn match, _slots -> link(match) end)
      |> protect_mentions(ctx)

    text
    |> escape()
    |> format()
    |> restore(slots)
  end

  # `render` gets the match and the slots so far and returns the HTML, or nil to leave the match
  defp protect({text, slots}, regex, render) do
    {parts, slots} =
      regex
      |> Regex.split(text, include_captures: true)
      |> Enum.with_index()
      |> Enum.map_reduce(slots, fn
        {match, i}, slots when rem(i, 2) == 1 ->
          case render.(match, slots) do
            nil ->
              {match, slots}

            html ->
              index = map_size(slots)
              {"\u{E000}#{index}\u{E001}", Map.put(slots, index, html)}
          end

        {text, _}, slots ->
          {text, slots}
      end)

    {Enum.join(parts), slots}
  end

  defp protect_mentions(acc, %{mentioned: mentioned} = ctx) do
    Enum.reduce(mentioned, acc, fn user, acc ->
      protect(acc, Mentions.mention_regex(user.name), fn _match, _slots -> mention(user, ctx) end)
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

  # `[text](url)`: the text is formatted like the rest of the line (code spans in it are already
  # slots), but has no links or mentions of its own: its URLs and mentions stay plain text.
  defp markdown_link(match, slots) do
    [_, text, url] = Regex.run(@markdown_link_regex, match)

    if http_url?(url) do
      inner = text |> escape() |> format() |> restore(slots)
      [~s(<a href="), escape(url), ~s(" target="_blank" rel="noopener">), inner, "</a>"]
    end
  end

  defp http_url?(url) do
    match?(
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and host not in [nil, ""],
      URI.parse(url)
    )
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
