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
