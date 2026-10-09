defmodule CampfireWeb.BrowserGateTest do
  use CampfireWeb.ConnCase, async: true

  import Campfire.Fixtures

  alias CampfireWeb.BrowserSupport

  @chrome "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/%s Safari/537.36"
  @safari "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/%s Safari/605.1.15"
  @firefox "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:%s) Gecko/20100101 Firefox/%s"
  @opera "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 OPR/%s"

  defp ua(template, version), do: String.replace(template, "%s", version)

  describe "BrowserSupport.blocked?/1" do
    test "chrome 120+" do
      assert BrowserSupport.blocked?(ua(@chrome, "119.0.6045.199"))
      refute BrowserSupport.blocked?(ua(@chrome, "120.0.0.0"))
      refute BrowserSupport.blocked?(ua(@chrome, "131.0.6778.86"))
      assert BrowserSupport.blocked?(ua(@chrome, "99.0.4844.51"))
    end

    test "safari 17.2+ compares dotted segments" do
      assert BrowserSupport.blocked?(ua(@safari, "17.1"))
      assert BrowserSupport.blocked?(ua(@safari, "16.6"))
      refute BrowserSupport.blocked?(ua(@safari, "17.2"))
      refute BrowserSupport.blocked?(ua(@safari, "17.2.1"))
      refute BrowserSupport.blocked?(ua(@safari, "17.10"))
      refute BrowserSupport.blocked?(ua(@safari, "18.0"))
    end

    test "firefox 121+, including Firefox on iOS" do
      assert BrowserSupport.blocked?(ua(@firefox, "120.0"))
      refute BrowserSupport.blocked?(ua(@firefox, "121.0"))

      assert BrowserSupport.blocked?(
               "Mozilla/5.0 (iPhone) AppleWebKit/605.1.15 FxiOS/120.0 Mobile/15E148 Safari/605.1.15"
             )

      refute BrowserSupport.blocked?(
               "Mozilla/5.0 (iPhone) AppleWebKit/605.1.15 FxiOS/121.0 Mobile/15E148 Safari/605.1.15"
             )
    end

    test "opera 104+ (it also carries a Chrome token that must not win)" do
      assert BrowserSupport.blocked?(ua(@opera, "103.0.0.0"))
      refute BrowserSupport.blocked?(ua(@opera, "104.0.0.0"))
      assert BrowserSupport.blocked?("Opera/9.80 (Windows NT 6.1) Presto/2.12.388 Version/12.16")
    end

    test "chrome on iOS follows CriOS" do
      assert BrowserSupport.blocked?(
               "Mozilla/5.0 (iPhone) AppleWebKit/605.1.15 CriOS/119.0.6045.169 Mobile/15E148 Safari/604.1"
             )

      refute BrowserSupport.blocked?(
               "Mozilla/5.0 (iPhone) AppleWebKit/605.1.15 CriOS/120.0.6099.119 Mobile/15E148 Safari/604.1"
             )
    end

    test "internet explorer is never supported" do
      assert BrowserSupport.blocked?(
               "Mozilla/4.0 (compatible; MSIE 9.0; Windows NT 6.1; Trident/5.0)"
             )

      assert BrowserSupport.blocked?(
               "Mozilla/5.0 (Windows NT 10.0; WOW64; Trident/7.0; rv:11.0) like Gecko"
             )
    end

    test "unlisted browsers, missing or odd user agents and bots pass" do
      # Edge isn't guarded, even though it carries an old-looking Chrome token
      refute BrowserSupport.blocked?(ua(@chrome, "100.0.0.0") <> " Edg/100.0.1185.29")

      refute BrowserSupport.blocked?(
               "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 Chrome/90.0 SamsungBrowser/14.0 Mobile Safari/537.36"
             )

      refute BrowserSupport.blocked?(nil)
      refute BrowserSupport.blocked?("")
      refute BrowserSupport.blocked?("curl/8.4.0")
      refute BrowserSupport.blocked?("SomeApp/1.0 CFNetwork/1494 Darwin/23.4.0")

      refute BrowserSupport.blocked?(
               "Mozilla/5.0 (iPhone) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
             )

      # Safari token without a Version/ is no Safari
      refute BrowserSupport.blocked?("Mozilla/5.0 (X11) AppleWebKit/605 Safari/605")
      # a crawler with an old evergreen Chrome token
      refute BrowserSupport.blocked?(
               "Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; Googlebot/2.1; +http://www.google.com/bot.html) Chrome/99.0.4844.84 Safari/537.36"
             )

      # Apple Messages link previews
      refute BrowserSupport.blocked?("facebookexternalhit/1.1 Facebot Twitterbot/1.0")
    end

    test "lists the guarded browsers in the original's order" do
      assert BrowserSupport.versions() ==
               [safari: "17.2", chrome: "120", firefox: "121", opera: "104", ie: false]
    end
  end

  describe "AllowBrowser plug" do
    setup do
      %{account: account_fixture()}
    end

    defp old_chrome(conn), do: put_req_header(conn, "user-agent", ua(@chrome, "100.0.0.0"))

    test "renders the incompatible browser page for an old browser", %{conn: conn} do
      conn = conn |> old_chrome() |> get(~p"/session/new")
      html = html_response(conn, 200)

      assert conn.halted
      assert html =~ "Upgrade to a supported web browser"
      assert html =~ "<title"
      assert html =~ "Unsupported browser"

      doc = LazyHTML.from_document(html)
      assert doc |> LazyHTML.query("#incompatible-browser.panel.center") |> Enum.count() == 1

      assert doc
             |> LazyHTML.query("details#translate-incompatible_browser_messsage")
             |> Enum.count() == 1

      assert doc
             |> LazyHTML.query("#incompatible-browser .browser-list > .browser")
             |> Enum.count() == 4

      assert doc
             |> LazyHTML.query("#browser-safari img[src='/images/browsers/safari.svg']")
             |> Enum.count() == 1

      assert html =~ "17.2+"
      assert html =~ "121+"
      refute html =~ "Ie"
      # the sign-in form is not served
      assert doc
             |> LazyHTML.query("input[name='user[password]'], input[type=password]")
             |> Enum.count() == 0
    end

    test "gates every browser-pipeline route, signed in or not", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> old_chrome() |> get(~p"/")
      assert html_response(conn, 200) =~ "Upgrade to a supported web browser"
    end

    test "supported browsers get the app", %{conn: conn} do
      conn =
        conn |> put_req_header("user-agent", ua(@chrome, "131.0.0.0")) |> get(~p"/session/new")

      assert html_response(conn, 200) =~ "Enter your password"
      refute conn.halted
    end

    test "requests without a user agent pass", %{conn: conn} do
      assert conn |> get(~p"/session/new") |> html_response(200) =~ "Enter your password"
    end

    test "the bot API and health check are not gated", %{conn: conn} do
      conn = conn |> old_chrome() |> get(~p"/up")
      assert conn.status == 200
    end

    test "static assets are not gated", %{conn: conn} do
      conn = conn |> old_chrome() |> get("/images/browsers/chrome.svg")
      assert response(conn, 200) =~ "<svg"
    end

    test "the page carries the account's custom styles", %{conn: conn, account: account} do
      account
      |> Ash.Changeset.for_update(:update, %{custom_styles: ".browser { color: red }"})
      |> Ash.update!(authorize?: false)

      html = conn |> old_chrome() |> get(~p"/session/new") |> html_response(200)
      assert html =~ ".browser { color: red }"
    end
  end
end
