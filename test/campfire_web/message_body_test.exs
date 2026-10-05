defmodule CampfireWeb.MessageBodyTest do
  use Campfire.DataCase, async: true

  import Campfire.Fixtures

  alias CampfireWeb.MessageBody

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

    assert result =~
             ~s(Hi <span class="mention"><img class="avatar" src="/users/#{ann.id}/avatar?v=)

    assert result =~ ~s( Ann Smith</span> and @Bob &lt;3)
    refute result =~ ~s(<span class="mention"><img class="avatar" src="/users/#{other.id})
  end

  test "loads mentioned users that aren't in the given map" do
    ann = user_fixture(name: "Ann")
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
