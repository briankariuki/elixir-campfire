defmodule CampfireWeb.CustomStylesLiveTest do
  use CampfireWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Campfire.Fixtures

  alias Campfire.Accounts
  alias CampfireWeb.CustomStyles

  setup do
    %{account: account_fixture()}
  end

  defp query(html, selector), do: html |> LazyHTML.from_document() |> LazyHTML.query(selector)

  describe "sanitize/1" do
    test "leaves ordinary CSS alone, selectors and quotes included" do
      css = ~s|main > p:not(.x) { content: "a & b"; color: red }\n/* ok */|
      assert CustomStyles.sanitize(css) == css
    end

    test "neutralises </style in any case, keeping the rest" do
      assert CustomStyles.sanitize("a{}</style><script>alert(1)</script>") ==
               "a{}<\\/style><script>alert(1)</script>"

      assert CustomStyles.sanitize("</STYLE >x</Style") == "<\\/STYLE >x<\\/Style"
    end

    test "neutralises <!--" do
      assert CustomStyles.sanitize("a{}<!-- x -->") == "a{}<\\!-- x -->"
    end

    test "blank or missing CSS is nil" do
      assert CustomStyles.sanitize(nil) == nil
      assert CustomStyles.sanitize("") == nil
      assert CustomStyles.sanitize(" \n ") == nil
    end
  end

  describe "root layout" do
    test "has no style element until the account has custom CSS", %{conn: conn} do
      html = conn |> get(~p"/session/new") |> html_response(200)
      assert Enum.empty?(query(html, "style#custom-styles"))
    end

    test "puts the CSS in <head> of every page, after app.css", %{conn: conn, account: account} do
      account
      |> Ash.Changeset.for_update(:update, %{custom_styles: "body > p { color: red }"})
      |> Ash.update!(authorize?: false)

      # a guests-only controller page
      html = conn |> get(~p"/session/new") |> html_response(200)
      assert [style] = query(html, "head style#custom-styles") |> Enum.to_list()
      assert LazyHTML.text(style) =~ "body > p { color: red }"
      assert html =~ "body > p { color: red }"
      assert :binary.match(html, "app.css") < :binary.match(html, "custom-styles")

      # a signed-in LiveView's first render
      user = user_fixture()
      html = conn |> log_in_user(user) |> get(~p"/profile") |> html_response(200)
      assert html =~ "body > p { color: red }"
    end

    test "can't be broken out of", %{conn: conn, account: account} do
      account
      |> Ash.Changeset.for_update(:update, %{
        custom_styles: "a{}</style><script id=\"pwned\">1</script><!-- x"
      })
      |> Ash.update!(authorize?: false)

      html = conn |> get(~p"/session/new") |> html_response(200)
      assert Enum.empty?(query(html, "script#pwned"))
      assert [_] = query(html, "style#custom-styles") |> Enum.to_list()
    end
  end

  describe "the editor" do
    test "is admin-only", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/account/custom_styles/edit")

      assert {:error, {:redirect, %{to: "/session/new"}}} =
               live(build_conn(), ~p"/account/custom_styles/edit")
    end

    test "is linked from the admin's account page only", %{conn: conn} do
      {:ok, view, _} = live(log_in_user(conn, admin_fixture()), ~p"/account")
      assert has_element?(view, "a[href='/account/custom_styles/edit']")

      {:ok, view, _} = live(log_in_user(build_conn(), user_fixture()), ~p"/account")
      refute has_element?(view, "a[href='/account/custom_styles/edit']")
    end

    test "saves the CSS and reloads so it applies", %{conn: conn, account: account} do
      admin = admin_fixture()
      {:ok, view, html} = conn |> log_in_user(admin) |> live(~p"/account/custom_styles/edit")

      assert has_element?(view, "#custom-styles-form textarea.input--code")
      assert has_element?(view, ".panel__button details#translate-custom_styles")
      assert html =~ "Use Caution: you could break things."

      css = "#main-content { background: hotpink }"

      {:error, {:redirect, %{to: to}}} =
        view |> form("#custom-styles-form", account: %{custom_styles: css}) |> render_submit()

      assert to == "/account/custom_styles/edit"
      assert Accounts.get_account!(authorize?: false).custom_styles == css
      assert account.id == Accounts.get_account!(authorize?: false).id

      # the next full page load carries the style
      page =
        conn |> log_in_user(admin) |> get(~p"/account/custom_styles/edit") |> html_response(200)

      assert page =~ css
    end

    test "clearing the textarea removes the styles", %{conn: conn, account: account} do
      account
      |> Ash.Changeset.for_update(:update, %{custom_styles: "a{color:red}"})
      |> Ash.update!(authorize?: false)

      {:ok, view, html} =
        conn |> log_in_user(admin_fixture()) |> live(~p"/account/custom_styles/edit")

      assert html =~ "a{color:red}"

      assert {:error, {:redirect, _}} =
               view
               |> form("#custom-styles-form", account: %{custom_styles: ""})
               |> render_submit()

      assert Accounts.get_account!(authorize?: false).custom_styles == nil
    end

    test "a member can't write styles through the domain", %{account: account} do
      member = user_fixture()

      assert {:error, %Ash.Error.Forbidden{}} =
               Accounts.update_account(account, %{custom_styles: "x{}"}, actor: member)
    end
  end
end
