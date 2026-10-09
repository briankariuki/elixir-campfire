defmodule Campfire.Chat.OpengraphTest do
  use Campfire.DataCase, async: true

  import Campfire.Fixtures

  alias Campfire.Broadcast
  alias Campfire.Chat
  alias Campfire.Chat.Opengraph
  alias Campfire.Chat.Opengraph.{Address, Fetch}

  @stub Campfire.Chat.Opengraph

  @page """
  <!doctype html>
  <html><head>
    <title>Fallback title</title>
    <meta name="description" content="Fallback description">
    <meta property="og:title" content="  The   Real Title ">
    <meta property="og:description" content="About the page">
    <meta property="og:image" content="/img/cover.png">
    <meta property="og:site_name" content="Example">
    <meta property="og:url" content="https://www.example.com/canonical">
  </head><body>Hello</body></html>
  """

  # Stubs the pages: `respond.(conn)` for each request, reporting `{:requested, host, path}` to
  # the test process (`conn.host` is the original host: the pinned address is a transport detail).
  defp stub_pages(respond) do
    test_pid = self()

    Req.Test.stub(@stub, fn conn ->
      send(test_pid, {:requested, conn.host, conn.request_path})
      respond.(conn)
    end)
  end

  defp html(conn, body, status \\ 200) do
    conn
    |> Plug.Conn.put_resp_content_type("text/html")
    |> Plug.Conn.send_resp(status, body)
  end

  defp stub_html(body), do: stub_pages(&html(&1, body))

  describe "first_url/1" do
    test "is the first http(s) link, without trailing punctuation" do
      assert Opengraph.first_url("see https://example.com/a?b=1, and http://other.example.com") ==
               "https://example.com/a?b=1"
    end

    test "ignores quoted lines, files and media, other schemes and a body without links" do
      assert Opengraph.first_url("> https://example.com/quoted\nhi") == nil

      assert Opengraph.first_url("https://example.com/cat.jpg then https://example.com/page") ==
               "https://example.com/page"

      assert Opengraph.first_url("https://example.com/archive.zip") == nil
      assert Opengraph.first_url("ftp://example.com/x and mailto:a@example.com") == nil
      assert Opengraph.first_url("just text, @Someone") == nil
      assert Opengraph.first_url("") == nil
      assert Opengraph.first_url(nil) == nil
    end

    test "ignores links with credentials and absurdly long links" do
      assert Opengraph.first_url("http://user:pw@example.com/") == nil
      assert Opengraph.first_url("https://example.com/" <> String.duplicate("a", 2100)) == nil
    end
  end

  describe "preview/1" do
    test "parses the OpenGraph tags" do
      stub_html(@page)

      assert {:ok, embed} = Opengraph.preview("https://example.com/post")

      assert embed == %{
               "url" => "https://www.example.com/canonical",
               "title" => "The Real Title",
               "description" => "About the page",
               "image_url" => "https://example.com/img/cover.png",
               "site_name" => "Example"
             }

      assert_received {:requested, "example.com", "/post"}
    end

    test "falls back to <title> and the meta description, and to the fetched url" do
      stub_html("""
      <html><head><title> Just a
        title </title><meta name="description" content="Plain description"></head></html>
      """)

      assert {:ok, embed} = Opengraph.preview("https://example.com/plain#frag")

      assert embed == %{
               "url" => "https://example.com/plain",
               "title" => "Just a title",
               "description" => "Plain description",
               "image_url" => nil,
               "site_name" => nil
             }
    end

    test "ignores an og:url on another host and an og:image that is not http(s)" do
      stub_html("""
      <meta property="og:title" content="T">
      <meta property="og:url" content="https://evil.example.org/phish">
      <meta property="og:image" content="javascript:alert(1)">
      """)

      assert {:ok, %{"url" => "https://example.com/p", "image_url" => nil}} =
               Opengraph.preview("https://example.com/p")

      stub_html(
        ~s(<meta property="og:title" content="T"><meta property="og:image" content="data:image/png;base64,AAAA">)
      )

      assert {:ok, %{"image_url" => nil}} = Opengraph.preview("https://example.com/p")

      stub_html(
        ~s(<meta property="og:title" content="T"><meta property="og:image" content="//cdn.example.com/a.png">)
      )

      assert {:ok, %{"image_url" => "https://cdn.example.com/a.png"}} =
               Opengraph.preview("https://example.com/p")
    end

    test "limits the lengths and strips markup characters from the text" do
      long = String.duplicate("word ", 300)

      stub_html(
        ~s(<meta property="og:title" content="#{long}"><meta property="og:description" content="#{long}">)
      )

      assert {:ok, embed} = Opengraph.preview("https://example.com/long")
      assert String.length(embed["title"]) == 280 and String.ends_with?(embed["title"], "…")
      assert String.length(embed["description"]) == 560
    end

    test "has nothing to show for a page without a title" do
      stub_html("<html><body>No head at all</body></html>")
      assert Opengraph.preview("https://example.com/none") == :none
    end

    test "reads ISO-8859-1 pages" do
      stub_pages(fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(200, <<"<title>Caf", 0xE9, "</title>">>)
      end)

      assert {:ok, %{"title" => "Café"}} = Opengraph.preview("https://example.com/latin1")
    end

    test "follows redirects (also relative ones), resolving the image against the final page" do
      stub_pages(fn
        %{request_path: "/start"} = conn ->
          conn |> Plug.Conn.put_resp_header("location", "/next") |> Plug.Conn.send_resp(301, "")

        %{request_path: "/next"} = conn ->
          conn
          |> Plug.Conn.put_resp_header("location", "http://other.example.com/final")
          |> Plug.Conn.send_resp(302, "")

        %{host: "other.example.com"} = conn ->
          html(
            conn,
            ~s(<meta property="og:title" content="Final"><meta property="og:image" content="x.png">)
          )
      end)

      assert {:ok, embed} = Opengraph.preview("https://example.com/start")
      assert embed["title"] == "Final"
      assert embed["image_url"] == "http://other.example.com/x.png"
      assert embed["url"] == "http://other.example.com/final"
    end

    test "gives up after a few redirects" do
      stub_pages(fn conn ->
        conn |> Plug.Conn.put_resp_header("location", "/again") |> Plug.Conn.send_resp(302, "")
      end)

      assert {:error, :too_many_redirects} = Opengraph.preview("https://example.com/loop")
      # the first request and 3 redirects
      for _ <- 1..4, do: assert_received({:requested, _, _})
      refute_received {:requested, _, _}
    end

    test "never raises, whatever the server does" do
      Req.Test.stub(@stub, fn _conn -> raise "boom" end)
      assert {:error, _} = Opengraph.preview("https://example.com/boom")

      Req.Test.stub(@stub, &Req.Test.transport_error(&1, :econnrefused))
      assert {:error, _} = Opengraph.preview("https://example.com/refused")
    end
  end

  describe "SSRF protections" do
    @refused [
      "http://127.0.0.1/",
      "http://127.1/",
      "http://2130706433/",
      "http://0.0.0.0/",
      "http://[::1]/",
      "http://[::ffff:127.0.0.1]/",
      "http://[::ffff:7f00:1]/",
      "http://169.254.169.254/latest/meta-data/",
      "http://[fe80::1]/",
      "http://[fd00::1]/",
      "http://10.1.2.3/",
      "http://172.16.0.1/",
      "http://192.168.1.1/",
      "http://100.64.0.1/",
      "http://224.0.0.1/",
      "http://255.255.255.255/",
      "http://[ff02::1]/",
      "http://localhost/",
      "http://internal.example.com/",
      "http://mapped.example.com/",
      "http://mixed.example.com/",
      "http://nonexistent.example.net/",
      "ftp://example.com/file",
      "file:///etc/passwd",
      "javascript:alert(1)",
      "gopher://example.com/",
      "http://user:pass@example.com/",
      "http:///nohost",
      "example.com/no-scheme"
    ]

    test "refuses private hosts, other schemes and bad URLs without making a request" do
      stub_html(@page)

      for url <- @refused do
        assert {:error, _} = Opengraph.preview(url), "#{url} should be refused"
      end

      refute_received {:requested, _, _}
    end

    test "re-checks every redirect" do
      for target <- [
            "http://127.0.0.1/admin",
            "http://internal.example.com/",
            "http://169.254.169.254/latest/meta-data/",
            "http://[::1]:4000/",
            "file:///etc/passwd",
            "ftp://example.com/"
          ] do
        stub_pages(fn conn ->
          conn |> Plug.Conn.put_resp_header("location", target) |> Plug.Conn.send_resp(302, "")
        end)

        assert {:error, _} = Opengraph.preview("https://example.com/redirect")
        assert_received {:requested, "example.com", "/redirect"}
        # only the first hop was requested
        refute_received {:requested, _, _}
      end
    end

    test "refuses responses that are not HTML" do
      stub_pages(fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, ~s({"title": "x"}))
      end)

      assert {:error, :not_html} = Opengraph.preview("https://example.com/api")

      stub_pages(fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("image/png")
        |> Plug.Conn.send_resp(200, "<title>x</title>")
      end)

      assert {:error, :not_html} = Opengraph.preview("https://example.com/image")
    end

    test "refuses error responses" do
      stub_pages(&html(&1, "<title>Not found</title>", 404))
      assert {:error, {:status, 404}} = Opengraph.preview("https://example.com/missing")
    end

    test "refuses bodies over 1 MB" do
      big = "<title>Big</title>" <> String.duplicate("a", Fetch.max_body())
      stub_html(big)
      assert {:error, :too_large} = Opengraph.preview("https://example.com/big")

      # exactly at the limit is fine
      ok = "<title>Ok</title>" <> String.duplicate("a", Fetch.max_body() - 17)
      stub_html(ok)
      assert {:ok, %{"title" => "Ok"}} = Opengraph.preview("https://example.com/ok")
    end
  end

  describe "Address.public?/1" do
    test "accepts global unicast addresses" do
      for ip <- [
            {8, 8, 8, 8},
            {93, 184, 216, 34},
            {1, 1, 1, 1},
            {172, 32, 0, 1},
            {100, 128, 0, 1}
          ],
          do: assert(Address.public?(ip), inspect(ip))

      for ip <- [
            {0x2606, 0x4700, 0x4700, 0, 0, 0, 0, 0x1111},
            {0x2001, 0x4860, 0x4860, 0, 0, 0, 0, 0x8888},
            {0, 0, 0, 0, 0, 0xFFFF, 0x0808, 0x0808}
          ],
          do: assert(Address.public?(ip), inspect(ip))
    end

    test "refuses reserved ranges, including those embedded in IPv6" do
      for ip <- [
            {0, 0, 0, 0},
            {127, 0, 0, 1},
            {10, 0, 0, 1},
            {172, 16, 0, 1},
            {172, 31, 255, 255},
            {192, 168, 0, 1},
            {169, 254, 169, 254},
            {100, 64, 0, 1},
            {192, 0, 2, 1},
            {198, 18, 0, 1},
            {224, 0, 0, 1},
            {240, 0, 0, 1},
            {255, 255, 255, 255},
            {0, 0, 0, 0, 0, 0, 0, 0},
            {0, 0, 0, 0, 0, 0, 0, 1},
            {0xFE80, 0, 0, 0, 0, 0, 0, 1},
            {0xFC00, 0, 0, 0, 0, 0, 0, 1},
            {0xFD12, 0x3456, 0, 0, 0, 0, 0, 1},
            {0xFF02, 0, 0, 0, 0, 0, 0, 1},
            {0x2001, 0xDB8, 0, 0, 0, 0, 0, 1},
            {0x2001, 0, 0, 0, 0, 0, 0, 1},
            # IPv4-mapped 127.0.0.1 and 10.0.0.1, NAT64 of 127.0.0.1, 6to4 of 10.0.0.1
            {0, 0, 0, 0, 0, 0xFFFF, 0x7F00, 1},
            {0, 0, 0, 0, 0, 0xFFFF, 0x0A00, 1},
            {0x64, 0xFF9B, 0, 0, 0, 0, 0x7F00, 1},
            {0x2002, 0x0A00, 0x0001, 0, 0, 0, 0, 1},
            # IPv4-compatible
            {0, 0, 0, 0, 0, 0, 0x7F00, 1}
          ],
          do: refute(Address.public?(ip), inspect(ip))
    end
  end

  describe "the transport" do
    defmodule EchoPlug do
      @moduledoc false
      @behaviour Elixir.Plug

      @impl true
      def init(opts), do: opts

      @impl true
      def call(conn, _opts) do
        case conn.request_path do
          "/echo" ->
            [host] = Elixir.Plug.Conn.get_req_header(conn, "host")

            Elixir.Plug.Conn.send_resp(
              conn,
              200,
              "#{host} #{conn.request_path}?#{conn.query_string}"
            )

          "/endless" ->
            conn = Elixir.Plug.Conn.send_chunked(conn, 200)

            Enum.reduce_while(1..3000, conn, fn _, conn ->
              case Elixir.Plug.Conn.chunk(conn, String.duplicate("x", 1024)) do
                {:ok, conn} -> {:cont, conn}
                {:error, _} -> {:halt, conn}
              end
            end)
        end
      end
    end

    setup do
      pid =
        start_supervised!({Bandit, plug: EchoPlug, port: 0, ip: :loopback, startup_log: false})

      {:ok, {_ip, port}} = ThousandIsland.listener_info(pid)
      %{port: port}
    end

    defp transport_request(url, ip, into) do
      Req.new(
        url: URI.parse(url),
        adapter: Campfire.Chat.Opengraph.Transport,
        into: into,
        retry: false,
        redirect: false
      )
      |> Req.Request.put_private(:opengraph, %{
        ip: ip,
        connect_timeout: 1_000,
        receive_timeout: 2_000,
        deadline: System.monotonic_time(:millisecond) + 5_000
      })
      |> Req.request()
    end

    test "connects to the given address and sends the original host", %{port: port} do
      collect = fn {:data, data}, {req, resp} ->
        {:cont,
         {req,
          Req.Response.put_private(resp, :body, Req.Response.get_private(resp, :body, "") <> data)}}
      end

      assert {:ok, response} =
               transport_request("http://example.com:#{port}/echo?a=1", {127, 0, 0, 1}, collect)

      assert response.status == 200
      assert Req.Response.get_private(response, :body) == "example.com:#{port} /echo?a=1"
    end

    test "stops reading when the into function halts", %{port: port} do
      halt = fn {:data, data}, {req, resp} ->
        size = Req.Response.get_private(resp, :size, 0) + byte_size(data)
        resp = Req.Response.put_private(resp, :size, size)
        if size > 10_000, do: {:halt, {req, resp}}, else: {:cont, {req, resp}}
      end

      assert {:ok, response} =
               transport_request("http://example.com:#{port}/endless", {127, 0, 0, 1}, halt)

      assert Req.Response.get_private(response, :size) < 1_000_000
    end

    test "reports connection errors" do
      collect = fn _chunk, acc -> {:cont, acc} end

      assert {:error, %Req.TransportError{}} =
               transport_request("http://example.com:1/", {127, 0, 0, 1}, collect)
    end
  end

  describe "messages" do
    setup do
      user = user_fixture(name: "Linker")
      room = open_room_fixture(user, "Links")
      Broadcast.subscribe_room(room.id)
      %{user: user, room: room}
    end

    defp stored_embed(message), do: reload(message).embed

    test "creating a message with a link stores the preview and broadcasts the update", %{
      user: user,
      room: room
    } do
      stub_html(@page)

      message = message_fixture(room, user, body: "Read https://example.com/post please")

      assert_received {:requested, "example.com", "/post"}
      assert_received {:message_created, %{id: id}} when id == message.id

      assert_received {:message_updated, updated}
      assert updated.id == message.id
      assert updated.embed["title"] == "The Real Title"
      # broadcasts carry what the web layer renders
      assert updated.creator.id == user.id
      assert updated.boosts == []

      assert stored_embed(message)["image_url"] == "https://example.com/img/cover.png"
    end

    test "a message without a link, with a quoted link, or with an attachment gets no job", %{
      user: user,
      room: room
    } do
      stub_html(@page)

      plain = message_fixture(room, user, body: "no link here")

      quoted =
        message_fixture(room, user, body: "> https://example.com/q\n— Ann /rooms/1/@2\n\nreply")

      attachment =
        message_fixture(room, user,
          body: "https://example.com/post",
          attachment_key: "k.png",
          attachment_filename: "k.png",
          attachment_content_type: "image/png",
          attachment_byte_size: 10
        )

      refute_received {:requested, _, _}
      refute_received {:message_updated, _}
      for message <- [plain, quoted, attachment], do: assert(stored_embed(message) == nil)
    end

    test "a link that cannot be previewed leaves no embed and broadcasts nothing", %{
      user: user,
      room: room
    } do
      stub_pages(&html(&1, "gone", 500))
      failed = message_fixture(room, user, body: "https://example.com/broken")

      stub_pages(fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/pdf")
        |> Plug.Conn.send_resp(200, "%PDF")
      end)

      not_html = message_fixture(room, user, body: "https://example.com/doc")

      private = message_fixture(room, user, body: "http://169.254.169.254/latest/meta-data")

      assert_received {:message_created, _}
      refute_received {:message_updated, _}
      for message <- [failed, not_html, private], do: assert(stored_embed(message) == nil)
    end

    test "editing the message to another link replaces the preview", %{user: user, room: room} do
      stub_pages(fn
        %{host: "other.example.com"} = conn ->
          html(conn, ~s(<meta property="og:title" content="Other page">))

        conn ->
          html(conn, @page)
      end)

      message = message_fixture(room, user, body: "https://example.com/post")
      assert stored_embed(message)["title"] == "The Real Title"

      updated =
        message
        |> reload()
        |> Chat.update_message!(%{body: "better: http://other.example.com/x"}, actor: user)

      # the edit itself cleared the embed (broadcast right away)...
      assert updated.embed == nil
      # ...and the job stored the new one
      assert stored_embed(message)["title"] == "Other page"
      assert_received {:message_updated, %{embed: %{"title" => "Other page"}}}
    end

    test "editing the message to remove the link clears the preview", %{user: user, room: room} do
      stub_html(@page)
      message = message_fixture(room, user, body: "https://example.com/post")
      assert stored_embed(message)

      message |> reload() |> Chat.update_message!(%{body: "never mind"}, actor: user)

      assert stored_embed(message) == nil
      assert_received {:message_updated, %{embed: nil, body: "never mind"}}
    end

    test "editing text around the same link keeps the preview without fetching again", %{
      user: user,
      room: room
    } do
      stub_html(@page)
      message = message_fixture(room, user, body: "https://example.com/post")
      assert_received {:requested, "example.com", "/post"}

      updated =
        message
        |> reload()
        |> Chat.update_message!(%{body: "typo fixed https://example.com/post"}, actor: user)

      assert updated.embed["title"] == "The Real Title"
      assert stored_embed(message)["title"] == "The Real Title"
      refute_received {:requested, _, _}
    end

    test "the embed can't be set through the public actions", %{user: user, room: room} do
      stub_html("<html></html>")
      message = message_fixture(room, user, body: "hi")

      assert {:error, _} =
               Chat.update_message(message, %{body: "hello", embed: %{"title" => "Injected"}},
                 actor: user
               )

      assert {:error, _} =
               Chat.create_message(room, %{body: "x", embed: %{"title" => "Injected"}},
                 actor: user
               )

      assert {:error, %Ash.Error.Forbidden{}} =
               message
               |> Ash.Changeset.for_update(:set_embed, %{embed: %{"title" => "x"}}, actor: user)
               |> Ash.update()
    end
  end
end
