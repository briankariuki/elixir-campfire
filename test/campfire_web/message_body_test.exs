defmodule CampfireWeb.MessageBodyTest do
  use Campfire.DataCase, async: true

  import Campfire.Fixtures

  alias CampfireWeb.{MessageBody, Paths}

  defp html(body, opts \\ []) do
    message = %{body: body, mentioned_user_ids: Keyword.get(opts, :mentioned, [])}

    message
    |> MessageBody.to_html(Keyword.get(opts, :users, %{}))
    |> Phoenix.HTML.safe_to_string()
  end

  test "wraps the body and escapes HTML" do
    assert html("<script>alert('x')</script> & co") ==
             ~s|<div class="lexxy-content">&lt;script&gt;alert(&#39;x&#39;)&lt;/script&gt; &amp; co</div>|
  end

  test "turns newlines into <br>" do
    assert html("one\ntwo\r\nthree") == ~s(<div class="lexxy-content">one<br>two<br>three</div>)
  end

  test "autolinks http(s) URLs, leaving trailing punctuation out" do
    assert html("See https://once.com/campfire?a=1&b=2.") ==
             ~s(<div class="lexxy-content">See <a href="https://once.com/campfire?a=1&amp;b=2" ) <>
               ~s(target="_blank" rel="noopener">https://once.com/campfire?a=1&amp;b=2</a>.</div>)

    refute html("javascript:alert(1) ftp://x") =~ "<a"
    refute html(~s|https://x.com/"onmouseover="alert(1)|) =~ ~s|"onmouseover|
  end

  test "turns > lines into blockquotes" do
    assert html("> quoted\n> more\nreply") ==
             ~s(<div class="lexxy-content"><blockquote>quoted<br>more</blockquote>reply</div>)

    assert html("a\n> b") == ~s(<div class="lexxy-content">a<blockquote>b</blockquote></div>)
    assert html(">not a quote") == ~s(<div class="lexxy-content">&gt;not a quote</div>)
  end

  test "highlights mentions of mentioned users" do
    ann = user_fixture(name: "Ann Smith")
    other = user_fixture(name: "Bob")

    result = html("Hi @Ann Smith and @Bob <3", mentioned: [ann.id], users: %{ann.id => ann})

    assert result =~ ~s(Hi <span class="mention"><a class="btn avatar" href="/users/#{ann.id}")
    assert result =~ ~s( Ann Smith</span> and @Bob &lt;3)
    refute result =~ ~s(href="/users/#{other.id}")
  end

  describe "mention links" do
    setup do
      ann = user_fixture(name: "Ann")
      %{ann: ann, opts: [mentioned: [ann.id], users: %{ann.id => ann}]}
    end

    test "the avatar links to the profile, like the original's users/_mention", %{
      ann: ann,
      opts: opts
    } do
      assert html("@Ann", opts) ==
               ~s(<div class="lexxy-content"><span class="mention">) <>
                 ~s(<a class="btn avatar" href="/users/#{ann.id}" title="Ann">) <>
                 ~s(<img src="#{Paths.avatar_path(ann)}" alt="" aria-hidden="true"></a> Ann</span></div>)
    end

    test "live: true adds the attributes <.link navigate> renders", %{ann: ann, opts: opts} do
      message = %{body: "@Ann", mentioned_user_ids: [ann.id]}

      live =
        message |> MessageBody.to_html(opts[:users], live: true) |> Phoenix.HTML.safe_to_string()

      assert live =~
               ~s(<a class="btn avatar" href="/users/#{ann.id}" title="Ann" ) <>
                 ~s(data-phx-link="redirect" data-phx-link-state="push">)

      refute html("@Ann", opts) =~ "data-phx"
      refute MessageBody.to_html_string(message, opts[:users]) =~ "data-phx"
    end
  end

  describe "reply attribution" do
    test "a line after a blockquote starting with an em dash is a <cite> with a # permalink" do
      assert html("> quoted\n— Ann Smith /rooms/1/@23\n\nreply") ==
               ~s(<div class="lexxy-content"><blockquote>quoted</blockquote>) <>
                 ~s(<cite>Ann Smith <a href="/rooms/1/@23">#</a></cite>reply</div>)

      assert html("> a\n> b\n— Ann /rooms/1/@23") ==
               ~s(<div class="lexxy-content"><blockquote>a<br>b</blockquote>) <>
                 ~s(<cite>Ann <a href="/rooms/1/@23">#</a></cite></div>)
    end

    test "the # link live-navigates inside a LiveView" do
      result =
        %{body: "> q\n— Ann /rooms/1/@2", mentioned_user_ids: []}
        |> MessageBody.to_html(%{}, live: true)
        |> Phoenix.HTML.safe_to_string()

      assert result =~
               ~s(<a href="/rooms/1/@2" data-phx-link="redirect" data-phx-link-state="push">#</a>)
    end

    test "a permalink URL on this site becomes the path; other hosts are plain text" do
      site = CampfireWeb.Endpoint.url()

      assert html("> q\n— Ann #{site}/rooms/1/@2") =~
               ~s(<cite>Ann <a href="/rooms/1/@2">#</a></cite>)

      for other <- [
            "https://evil.example/rooms/1/@2",
            "/rooms/1/@2/x",
            "/users/2",
            "javascript:alert(1)"
          ] do
        result = html("> q\n— Ann #{other}")
        refute result =~ "<cite>Ann <a"

        assert result =~
                 "<cite>Ann #{other |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()}</cite>"
      end
    end

    test "an attribution without a permalink is an escaped <cite>" do
      assert html("> To be\n— <i>Hamlet</i> & co") ==
               ~s(<div class="lexxy-content"><blockquote>To be</blockquote>) <>
                 ~s(<cite>&lt;i&gt;Hamlet&lt;/i&gt; &amp; co</cite></div>)

      assert html("> q\n— Ann <script> /rooms/1/@2") =~
               ~s(<cite>Ann &lt;script&gt; <a href="/rooms/1/@2">#</a></cite>)
    end

    test "only the line right after a blockquote is an attribution" do
      assert html("— Ann /rooms/1/@2") == ~s(<div class="lexxy-content">— Ann /rooms/1/@2</div>)

      refute html("> q\nhi\n— Ann /rooms/1/@2") =~ "<cite>"
      refute html("> q\n\n— Ann /rooms/1/@2") =~ "<cite>"
    end

    test "keeps the reply text and mentions after the attribution" do
      ann = user_fixture(name: "Ann")

      result =
        html("> hi\n— Bob /rooms/1/@2\n\n@Ann thanks\nbye",
          mentioned: [ann.id],
          users: %{ann.id => ann}
        )

      assert result =~ ~s(</cite><span class="mention">)
      assert result =~ "Ann</span> thanks<br>bye</div>"
    end
  end

  describe "reply_text/2" do
    setup do
      %{room: %{id: 3}, author: user_fixture(name: "Ann Smith")}
    end

    defp reply_text(author, room_id, body, extra \\ %{}) do
      message =
        Map.merge(
          %{id: 7, room_id: room_id, body: body, mentioned_user_ids: [], creator: author},
          extra
        )

      MessageBody.reply_text(message)
    end

    test "quotes every line and attributes the author", %{room: room, author: author} do
      assert reply_text(author, room.id, "one\ntwo\n\nthree") ==
               "> one\n> two\n>\n> three\n— Ann Smith /rooms/#{room.id}/@7\n\n"
    end

    test "leaves out nested quotes and the earlier attribution", %{room: room, author: author} do
      body = "> old\n— Bob /rooms/1/@2\n\nnew thought"

      assert reply_text(author, room.id, body) ==
               "> new thought\n— Ann Smith /rooms/#{room.id}/@7\n\n"
    end

    test "drops the @ of mentions so the reply doesn't notify again", %{
      room: room,
      author: author
    } do
      bob = user_fixture(name: "Bob")

      assert reply_text(author, room.id, "hi @Bob, and @Nobody", %{mentioned_user_ids: [bob.id]}) ==
               "> hi Bob, and @Nobody\n— Ann Smith /rooms/#{room.id}/@7\n\n"
    end

    test "a /play message quotes the sound's caption", %{room: room, author: author} do
      assert reply_text(author, room.id, "/play tada") ==
               "> plays a fanfare 🎏\n— Ann Smith /rooms/#{room.id}/@7\n\n"

      assert reply_text(author, room.id, "/play nyan") ==
               "> 🔊 nyan\n— Ann Smith /rooms/#{room.id}/@7\n\n"

      # not a known sound: an ordinary text message
      assert reply_text(author, room.id, "/play nope") =~ "> /play nope\n"
    end

    test "the prefilled text renders as blockquote + cite", %{room: room, author: author} do
      text = reply_text(author, room.id, "line one\nline two") <> "Agreed"

      assert html(text) ==
               ~s(<div class="lexxy-content"><blockquote>line one<br>line two</blockquote>) <>
                 ~s(<cite>Ann Smith <a href="/rooms/#{room.id}/@7">#</a></cite>Agreed</div>)
    end
  end

  describe "inline formatting" do
    defp wrapped(inner), do: ~s(<div class="lexxy-content">#{inner}</div>)

    test "bold, italic, strike, highlight and code" do
      assert html("**b** *i* _i_ ~~s~~ ==h== `c`") ==
               wrapped(
                 "<strong>b</strong> <em>i</em> <em>i</em> <s>s</s> <mark>h</mark> <code>c</code>"
               )

      assert html("***both***") == wrapped("<strong><em>both</em></strong>")
      assert html("**a *b* c**") == wrapped("<strong>a <em>b</em> c</strong>")
      assert html("*a **b** c*") == wrapped("<em>a <strong>b</strong> c</em>")
    end

    test "markers must hug the text and don't apply inside words" do
      for text <- ["2 * 3 * 4", "snake_case_name", "a * b*", "** a**", "__init__", "x == y == z"] do
        assert html(text) == wrapped(text)
      end

      assert html("an unmatched **marker") == wrapped("an unmatched **marker")
    end

    test "formatting never lets HTML through" do
      result = html("**<script>alert(1)</script>** _<img src=x onerror=y>_ ==&==")

      assert result ==
               wrapped(
                 "<strong>&lt;script&gt;alert(1)&lt;/script&gt;</strong> " <>
                   "<em>&lt;img src=x onerror=y&gt;</em> <mark>&amp;</mark>"
               )

      refute html(~s(`</code><script>`)) =~ "<script"
    end

    test "inline code is literal: no formatting, links or mentions" do
      ann = user_fixture(name: "Ann")
      opts = [mentioned: [ann.id], users: %{ann.id => ann}]

      assert html("`**x** https://x.com @Ann`", opts) ==
               wrapped("<code>**x** https://x.com @Ann</code>")

      assert html("@Ann `@Ann`", opts) =~ ~s(</span> <code>@Ann</code>)
    end

    test "URLs and mentions inside formatting keep working" do
      ann = user_fixture(name: "Ann")
      opts = [mentioned: [ann.id], users: %{ann.id => ann}]

      result = html("**https://x.com/a_b_c** and ==@Ann==", opts)

      assert result =~
               ~s(<strong><a href="https://x.com/a_b_c" target="_blank" rel="noopener">https://x.com/a_b_c</a></strong>)

      assert result =~ ~s(<mark><span class="mention">)
      assert result =~ "Ann</span></mark>"
    end

    test "a URL's own underscores and stars aren't formatting" do
      result = html("https://x.com/_a_/*b*")
      assert result =~ ~s(href="https://x.com/_a_/*b")
      refute result =~ "<em>"
    end

    test "placeholder characters in the text can't forge a slot" do
      assert html("x\u{E000}0\u{E001}y `c`") == wrapped("x0y <code>c</code>")
    end
  end

  describe "blocks" do
    test "# makes an h1, only a single # does" do
      assert html("# Title **x**\nbody") == wrapped("<h1>Title <strong>x</strong></h1>body")

      for text <- ["## two", "#tag", "#", "# ", "a # b"] do
        refute html(text) =~ "<h1"
      end
    end

    test "- and * make bullet lists, N. numbered lists" do
      assert html("- a\n* b *i*\nafter") ==
               wrapped("<ul><li>a</li><li>b <em>i</em></li></ul>after")

      assert html("1. a\n2. b") == wrapped("<ol><li>a</li><li>b</li></ol>")
      assert html("3. a\n4. b") == wrapped(~s(<ol start="3"><li>a</li><li>b</li></ol>))

      assert html("- a\n1. b") == wrapped("<ul><li>a</li></ul><ol><li>b</li></ol>")

      for text <- ["-a", "*a*", "- ", "1.5 hours", "1) a", " - indented"] do
        refute html(text) =~ "<li"
      end
    end

    test "indented items nest lists inside the parent item" do
      assert html("- a\n  - b\n  - c\n- d") ==
               wrapped("<ul><li>a<ul><li>b</li><li>c</li></ul></li><li>d</li></ul>")

      assert html("- a\n\t- b") == wrapped("<ul><li>a<ul><li>b</li></ul></li></ul>")
      assert html("- a\n    - b") == wrapped("<ul><li>a<ul><li>b</li></ul></li></ul>")

      assert html("- a\n  * b *i*") ==
               wrapped("<ul><li>a<ul><li>b <em>i</em></li></ul></li></ul>")
    end

    test "bullets and numbers nest in each other" do
      assert html("1. a\n  - b\n  - c\n2. d") ==
               wrapped("<ol><li>a<ul><li>b</li><li>c</li></ul></li><li>d</li></ol>")

      assert html("- a\n  3. b\n  4. c") ==
               wrapped(~s(<ul><li>a<ol start="3"><li>b</li><li>c</li></ol></li></ul>))

      # another kind at the same level starts another list next to it
      assert html("- a\n  1. b\n  - c") ==
               wrapped("<ul><li>a<ol><li>b</li></ol><ul><li>c</li></ul></li></ul>")
    end

    test "up to four levels, deeper indentation stays on the last one" do
      assert html("- 1\n  - 2\n    - 3\n      - 4\n        - 5\n          - 6\n  - back") ==
               wrapped(
                 "<ul><li>1<ul><li>2<ul><li>3<ul><li>4</li><li>5</li><li>6</li></ul></li></ul></li>" <>
                   "<li>back</li></ul></li></ul>"
               )

      assert html("- a\n          - b") == wrapped("<ul><li>a<ul><li>b</li></ul></li></ul>")
    end

    test "dedenting goes back to a level, an uneven one to the deeper level" do
      assert html("- a\n    - b\n  - c\n- d") ==
               wrapped("<ul><li>a<ul><li>b</li><li>c</li></ul></li><li>d</li></ul>")

      assert html("- a\n  - b\n    - c\n  - d\n- e") ==
               wrapped(
                 "<ul><li>a<ul><li>b<ul><li>c</li></ul></li><li>d</li></ul></li><li>e</li></ul>"
               )
    end

    test "a list starts on an unindented item, one space is no indent" do
      for text <- ["  - a", "\t- a", "text\n  - a", " - a"] do
        refute html(text) =~ "<li", text
      end

      assert html("- a\n - b") == wrapped("<ul><li>a</li></ul> - b")
    end

    test "nested lists work in quotes, and replies quote them as typed" do
      assert html("> - a\n>   1. b\n> - c") ==
               wrapped(
                 "<blockquote><ul><li>a<ol><li>b</li></ol></li><li>c</li></ul></blockquote>"
               )

      author = user_fixture(name: "Ann Smith")

      text =
        MessageBody.reply_text(%{
          id: 7,
          room_id: 3,
          body: "- a\n  - b",
          mentioned_user_ids: [],
          creator: author
        })

      assert text == "> - a\n>   - b\n— Ann Smith /rooms/3/@7\n\n"

      assert html(text <> "ok") =~
               "<blockquote><ul><li>a<ul><li>b</li></ul></li></ul></blockquote>"
    end

    test "no <br> or empty line around blocks, but blank lines elsewhere stay" do
      assert html("intro\n\n- a\n\nafter") == wrapped("intro<ul><li>a</li></ul>after")
      assert html("a\n\nb") == wrapped("a<br><br>b")
    end

    test "fenced code becomes <pre><code> and is literal" do
      ann = user_fixture(name: "Ann")
      opts = [mentioned: [ann.id], users: %{ann.id => ann}]

      assert html("```\nputs <b>\n\n  **x** @Ann https://x.com\n> q\n# h\n```", opts) ==
               wrapped(
                 "<pre><code>puts &lt;b&gt;\n\n  **x** @Ann https://x.com\n&gt; q\n# h</code></pre>"
               )

      assert html("a\n```ruby\nx\n```\nb") ==
               wrapped(~s(a<pre data-language="ruby"><code>x</code></pre>b))
    end

    test "an unclosed or odd fence is plain text" do
      assert html("```\nunclosed") == wrapped("```<br>unclosed")
      refute html("```\nunclosed") =~ "<pre"
      refute html("``` not a fence\nx\n```") =~ "<pre"
      refute html(~s(```"><script>\nx\n```)) =~ "<script"
    end

    test "quotes hold blocks, but no nested quotes" do
      assert html("> # h\n> - a\n> ```\n> **x**\n> ```") ==
               wrapped(
                 "<blockquote><h1>h</h1><ul><li>a</li></ul><pre><code>**x**</code></pre></blockquote>"
               )

      assert html("> a\n> > b") == wrapped("<blockquote>a<br>&gt; b</blockquote>")
    end

    test "a formatted reply renders as a quote with formatting and a cite" do
      assert html("> **bold** and `code`\n— Ann /rooms/1/@2\n\nreply") ==
               wrapped(
                 "<blockquote><strong>bold</strong> and <code>code</code></blockquote>" <>
                   ~s(<cite>Ann <a href="/rooms/1/@2">#</a></cite>reply)
               )
    end
  end

  describe "links" do
    defp link(href, text), do: ~s(<a href="#{href}" target="_blank" rel="noopener">#{text}</a>)

    test "[text](url) becomes a link that opens in a new tab" do
      assert html("[Elixir](https://elixir-lang.org)") ==
               wrapped(link("https://elixir-lang.org", "Elixir"))

      assert html("go [here](http://x.com/a?b=1) now") ==
               wrapped("go " <> link("http://x.com/a?b=1", "here") <> " now")
    end

    test "the href is escaped" do
      assert html("[a](https://x.com/?a=1&b='2')") ==
               wrapped(link("https://x.com/?a=1&amp;b=&#39;2&#39;", "a"))

      # a quote ends the URL, so it can't break out of the attribute: it isn't a link at all
      result = html(~S|[a](https://x.com/"onclick="alert(1))|)
      refute result =~ ~S|onclick="|
      refute result =~ ">a</a>"
    end

    test "only absolute http(s) URLs with a host are links" do
      for text <- [
            "[a](javascript:alert(1))",
            "[a](JavaScript:alert(1))",
            "[a](data:text/html,x)",
            "[a](vbscript:x)",
            "[a](//x.com)",
            "[a](/rooms/1)",
            "[a](x.com)",
            "[a](ftp://x.com)",
            "[a](https://)",
            "[a](https:///path)",
            "[a](https:x.com)",
            "[a]( https://x.com)",
            "[a](https://x.com",
            "[a] (https://x.com)",
            "[](https://x.com)",
            "[ ](https://x.com)",
            "[a(https://x.com)"
          ] do
        result = html(text)
        refute result =~ ~S|href="javascript|, text
        refute result =~ ~S|href="data|, text
        refute result =~ ~S|href="vbscript|, text
        refute result =~ ">a</a>", text
        refute result =~ "<a></a>", text
      end

      assert html("[a](javascript:alert(1))") == wrapped("[a](javascript:alert(1))")
      assert html("[a](/rooms/1)") == wrapped("[a](/rooms/1)")
      assert html("[a](data:text/html,<b>)") == wrapped("[a](data:text/html,&lt;b&gt;)")
      assert html("[](https://)") == wrapped("[](https://)")
    end

    test "the text is formatted, and may hold code, but is no link, URL or mention" do
      ann = user_fixture(name: "Ann")
      opts = [mentioned: [ann.id], users: %{ann.id => ann}]

      assert html("[**bold** _it_ ~~s~~ ==h== `a_b`](https://x.com)") ==
               wrapped(
                 link(
                   "https://x.com",
                   "<strong>bold</strong> <em>it</em> <s>s</s> <mark>h</mark> <code>a_b</code>"
                 )
               )

      assert html("**[a](https://x.com)**") ==
               wrapped("<strong>" <> link("https://x.com", "a") <> "</strong>")

      # not linked twice, and the mention is plain text
      assert html("[https://a.com](https://b.com)") ==
               wrapped(link("https://b.com", "https://a.com"))

      assert html("[@Ann](https://x.com)", opts) == wrapped(link("https://x.com", "@Ann"))
      assert html("[a [b](https://x.com)](https://y.com)") =~ link("https://x.com", "b")
    end

    test "balanced parentheses belong to the URL, an extra closing one to the text" do
      wiki = "https://en.wikipedia.org/wiki/Elixir_(programming_language)"

      assert html("[Elixir](#{wiki})") == wrapped(link(wiki, "Elixir"))
      assert html("(see [Elixir](#{wiki}))") == wrapped("(see " <> link(wiki, "Elixir") <> ")")
      assert html("([a](https://x.com/a))") == wrapped("(" <> link("https://x.com/a", "a") <> ")")
      assert html("[a](https://x.com/(b)(c)/d)") == wrapped(link("https://x.com/(b)(c)/d", "a"))
      assert html("[a](https://x.com/a)).") == wrapped(link("https://x.com/a", "a") <> ").")

      # unbalanced: not a link, the bare URL is autolinked up to its last character
      assert html("[a](https://x.com/(b)") =~ "[a]("
      refute html("[a](https://x.com/(b)") =~ ~s(">a</a>)
    end

    test "links are not made in code, and a bare URL is still autolinked" do
      assert html("`[a](https://x.com)`") == wrapped("<code>[a](https://x.com)</code>")

      assert html("```\n[a](https://x.com)\n```") ==
               wrapped("<pre><code>[a](https://x.com)</code></pre>")

      assert html("[a](https://x.com) and https://y.com") ==
               wrapped(
                 link("https://x.com", "a") <> " and " <> link("https://y.com", "https://y.com")
               )
    end

    test "links work in headings, lists and quotes" do
      assert html("# [a](https://x.com)\n- [b](https://y.com)\n> [c](https://z.com)") ==
               wrapped(
                 "<h1>#{link("https://x.com", "a")}</h1><ul><li>#{link("https://y.com", "b")}</li></ul>" <>
                   "<blockquote>#{link("https://z.com", "c")}</blockquote>"
               )
    end

    test "replies quote the source text of a link" do
      author = user_fixture(name: "Ann Smith")

      text =
        MessageBody.reply_text(%{
          id: 7,
          room_id: 3,
          body: "see [docs](https://x.com/a_(b)) now",
          mentioned_user_ids: [],
          creator: author
        })

      assert text == "> see [docs](https://x.com/a_(b)) now\n— Ann Smith /rooms/3/@7\n\n"
      assert html(text <> "ok") =~ ~S|<blockquote>see <a href="https://x.com/a_(b)"|
    end
  end

  describe "reply_text/2 with formatting" do
    test "quotes the source text, code blocks included" do
      author = user_fixture(name: "Ann Smith")
      body = "# T\n**b**\n```\n> keep\n\n— keep too\n```\n- x"

      text =
        MessageBody.reply_text(%{
          id: 7,
          room_id: 3,
          body: body,
          mentioned_user_ids: [],
          creator: author
        })

      assert text ==
               "> # T\n> **b**\n> ```\n> > keep\n>\n> — keep too\n> ```\n> - x\n— Ann Smith /rooms/3/@7\n\n"

      rendered = html(text <> "ok")

      assert rendered =~
               "<blockquote><h1>T</h1><strong>b</strong><pre><code>&gt; keep\n\n— keep too</code></pre><ul><li>x</li></ul></blockquote>"

      assert rendered =~ "<cite>Ann Smith"
    end

    test "doesn't strip mentions inside code" do
      ann = user_fixture(name: "Ann")
      bob = user_fixture(name: "Bob")

      text =
        MessageBody.reply_text(%{
          id: 1,
          room_id: 1,
          body: "hi @Ann\n```\n@Ann\n```",
          mentioned_user_ids: [ann.id],
          creator: bob
        })

      assert text =~ "> hi Ann\n> ```\n> @Ann\n> ```\n"
    end
  end

  test "loads mentioned users that aren't in the given map" do
    ann = user_fixture(name: "Ann")
    assert html("@Ann!", mentioned: [ann.id]) =~ ~s(href="/users/#{ann.id}")
    assert html("@Ann!", mentioned: [ann.id]) =~ ~s(Ann</span>!)
  end

  test "escapes mentioned names and doesn't match longer words" do
    user = user_fixture(name: "O'Brien <b>")
    users = %{user.id => user}

    result = html("@O'Brien <b> hi", mentioned: [user.id], users: users)
    assert result =~ "O&#39;Brien &lt;b&gt;</span> hi"
    refute result =~ "<b>"

    assert html("@Annabel", mentioned: [user.id], users: users) =~ "@Annabel"
  end

  test "doesn't highlight @Name inside a word, like an email address" do
    ann = user_fixture(name: "Ann")
    opts = [mentioned: [ann.id], users: %{ann.id => ann}]

    assert html("x@Ann", opts) == ~s(<div class="lexxy-content">x@Ann</div>)
    assert html("mail bob@Ann.com", opts) == ~s(<div class="lexxy-content">mail bob@Ann.com</div>)

    result = html("bob@Ann.com, (@Ann)\n@Ann", opts)
    assert result =~ ~s(<div class="lexxy-content">bob@Ann.com, (<span class="mention">)
    assert result =~ ~s[Ann</span>)<br><span class="mention">]
    assert length(String.split(result, ~s(<span class="mention">))) == 3
  end

  test "emoji_only?/1" do
    assert MessageBody.emoji_only?("🎉🔥")
    assert MessageBody.emoji_only?(" ❤️ 👍🏽 ")
    refute MessageBody.emoji_only?("nice 🎉")
    refute MessageBody.emoji_only?("123")
    refute MessageBody.emoji_only?("")
    refute MessageBody.emoji_only?(nil)
  end
end
