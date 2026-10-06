defmodule CampfireWeb.QrAndTranslationsTest do
  use CampfireWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Campfire.Fixtures

  alias CampfireWeb.{QRCode, Translations}

  defp query(html, selector), do: html |> LazyHTML.from_document() |> LazyHTML.query(selector)
  defp count(html, selector), do: html |> query(selector) |> Enum.count()

  describe "CampfireWeb.QRCode" do
    test "renders a self-contained SVG with a quiet zone" do
      svg = QRCode.svg("http://localhost/join/abc")

      assert String.starts_with?(svg, ~s(<svg xmlns="http://www.w3.org/2000/svg" viewBox="-2 -2 ))
      assert svg =~ ~s(fill="#fff")
      assert svg =~ ~r/<path d="M\d+ \d+h\d+v1h-\d+z/
      assert String.ends_with?(svg, "</svg>")
      # compact: one path, not a rect per module
      refute svg =~ "<rect x=\"1\""
      assert byte_size(svg) < 20_000
    end

    test "is deterministic and differs per input" do
      assert QRCode.svg("a") == QRCode.svg("a")
      refute QRCode.svg("a") == QRCode.svg("b")
    end

    test "data_uri/1 is a base64 SVG data URI" do
      uri = QRCode.data_uri("http://localhost/join/abc")
      assert "data:image/svg+xml;base64," <> encoded = uri
      assert Base.decode64!(encoded) == QRCode.svg("http://localhost/join/abc")
    end
  end

  describe "QR buttons" do
    setup :register_and_log_in_user

    test "the account page shows the join link QR code in the lightbox", %{conn: conn} do
      account = account_fixture()
      {:ok, view, html} = live(conn, ~p"/account")

      assert has_element?(view, "#invite[phx-hook=Lightbox]")

      assert [href] =
               html
               |> query("#invite a#qr-invite-url[data-lightbox]")
               |> LazyHTML.attribute("href")

      assert "data:image/svg+xml;base64," <> encoded = href
      svg = Base.decode64!(encoded)
      assert svg == QRCode.svg(url(~p"/join/#{account.join_code}"))
      assert has_element?(view, "#qr-invite-url .for-screen-reader", "Show join link QR code")
      assert has_element?(view, "#qr-invite-url img[src='/images/qr-code.svg']")
    end

    test "the welcome card reuses the room's lightbox", %{conn: conn, user: user} do
      original = open_room_fixture(user, "All Talk")
      {:ok, view, _html} = live(conn, ~p"/rooms/#{original.id}")

      assert has_element?(view, "#message-area[phx-hook=Lightbox] #system_welcome #qr-invite-url")
      # no second Lightbox hook, or one click would open the dialog twice
      refute has_element?(view, "#system_welcome #invite[phx-hook]")
    end

    test "the profile page shows the auto-login QR code", %{conn: conn, user: user} do
      {:ok, view, html} = live(conn, ~p"/profile")

      assert has_element?(
               view,
               "#transfer-link[phx-hook=Lightbox] a#qr-transfer-url[data-lightbox]"
             )

      assert [href] = html |> query("#qr-transfer-url") |> LazyHTML.attribute("href")
      assert String.starts_with?(href, "data:image/svg+xml;base64,")
      assert has_element?(view, "#qr-transfer-url .for-screen-reader", "Show auto-login QR code")
      assert has_element?(view, "#session_transfer_url")
      assert user
    end

    test "an admin sees the QR code for another user's transfer link", %{conn: conn} do
      other = user_fixture()
      {:ok, view, _html} = live(log_in_user(conn, admin_fixture()), ~p"/users/#{other.id}")

      assert has_element?(view, "#transfer-link a#qr-transfer-url[data-lightbox]")
    end
  end

  describe "CampfireWeb.Translations" do
    test "has the original's keys, each in seven languages with the original flags" do
      assert Translations.keys() ==
               ~w(email_address password update_password user_name account_name room_name
                  invite_message incompatible_browser_messsage bio webhook_url chat_bots bot_name
                  custom_styles)a

      for key <- Translations.keys() do
        assert Translations.translations_for(key) |> Enum.map(&elem(&1, 0)) ==
                 ["🇺🇸", "🇪🇸", "🇫🇷", "🇮🇳", "🇩🇪", "🇧🇷", "🇯🇵"]
      end

      assert {"🇫🇷", "Entrez votre adresse courriel"} =
               Translations.translations_for(:email_address) |> Enum.at(2)
    end

    test "an unknown key raises" do
      assert_raise KeyError, fn -> Translations.translations_for(:nope) end
    end

    test "the button is the original's details/summary/menu markup" do
      html = render_component(&Translations.translation_button/1, key: :password)

      assert count(
               html,
               "details#translate-password.position-relative[data-popup][phx-update=ignore]"
             ) == 1

      assert count(html, "details > summary.btn[tabindex='-1'] img[src='/images/globe.svg']") == 1
      assert count(html, "summary .for-screen-reader") == 1
      assert count(html, "details > div.language-list-menu.shadow dl.language-list") == 1
      assert count(html, "dl.language-list > dt") == 7
      assert count(html, "dl.language-list > dd.margin-none") == 7
      assert html =~ "Enter your password"
      assert html =~ "Insira sua senha"
    end

    test "an explicit id lets one key appear twice" do
      html = render_component(&Translations.translation_button/1, key: :bio, id: "bio-tr")
      assert count(html, "details#bio-tr") == 1
    end
  end

  describe "translation buttons on the pages" do
    test "first run", %{conn: conn} do
      html = conn |> get(~p"/first_run") |> html_response(200)

      for key <- ~w(user_name email_address password) do
        assert count(html, "details#translate-#{key}") == 1
      end
    end

    test "sign in and join" do
      account = account_fixture()

      for path <- [~p"/session/new", ~p"/join/#{account.join_code}"] do
        html = build_conn() |> get(path) |> html_response(200)
        assert count(html, "details#translate-email_address") == 1
        assert count(html, "details#translate-password") == 1
      end

      html = build_conn() |> get(~p"/join/#{account.join_code}") |> html_response(200)
      assert count(html, "details#translate-user_name") == 1
    end

    test "account, bots, profile and the welcome card", %{conn: conn} do
      account_fixture()
      admin = admin_fixture()
      conn = log_in_user(conn, admin)

      {:ok, view, _} = live(conn, ~p"/account")
      assert has_element?(view, "#account-name-form details#translate-account_name")

      {:ok, view, _} = live(conn, ~p"/account/bots")
      assert has_element?(view, ".panel__button details#translate-chat_bots")

      {:ok, view, _} = live(conn, ~p"/account/bots/new")
      assert has_element?(view, "#bot-form details#translate-bot_name")
      assert has_element?(view, "#bot-form details#translate-webhook_url")

      {:ok, view, _} = live(conn, ~p"/profile")

      for key <- ~w(user_name email_address update_password bio) do
        assert has_element?(view, "#profile-form details#translate-#{key}")
      end

      original = open_room_fixture(admin, "All Talk")
      {:ok, view, _} = live(conn, ~p"/rooms/#{original.id}")

      assert has_element?(
               view,
               "#system_welcome .system-welcome--translation details#translate-invite_message"
             )
    end
  end
end
