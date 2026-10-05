defmodule CampfireWeb.CoreComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import CampfireWeb.CoreComponents

  test "icon_button renders a round .btn with icon and screen-reader label" do
    html = render_component(&icon_button/1, icon: "search", label: "Search", variant: "reversed")

    assert html =~ ~s(class="btn btn--reversed")
    assert html =~ ~s(src="/images/search.svg")
    assert html =~ ~s(<span class="for-screen-reader">Search</span>)

    html =
      render_component(&icon_button/1, icon: "search", label: "Search", navigate: "/searches")

    assert html =~ ~s(href="/searches")
  end

  test "input with an icon renders the input--actor variant" do
    form = to_form(%{"email" => "a@b.c"}, as: :user)
    html = render_component(&input/1, field: form[:email], type: "email", icon: "email")

    assert html =~ "input input--actor"
    assert html =~ ~s(name="user[email]")
    assert html =~ ~s(value="a@b.c")
    assert html =~ ~s(src="/images/email.svg")
  end

  test "plain input and textarea get the .input class" do
    assert render_component(&input/1, name: "q", value: "x") =~ ~s(class="input")

    html = render_component(&input/1, name: "bio", value: "Hi", type: "textarea")
    assert html =~ ~r/<textarea[^>]*class="input"/
  end

  test "switch, avatar and flash" do
    html = render_component(&switch/1, name: "restrict", checked: true, label: "Restrict")
    assert html =~ ~s(class="switch__input")
    assert html =~ "switch__btn round"
    assert html =~ "checked"

    html = render_component(&avatar/1, src: "/a.png", size: "10ch", navigate: "/users/1")
    assert html =~ ~s(style="--avatar-size: 10ch")
    assert html =~ ~s(class="btn avatar")

    html = render_component(&flash/1, kind: :error, flash: %{"error" => "Nope"})
    assert html =~ "flash__inner"
    assert html =~ "Nope"
    assert html =~ "/images/alert.svg"
  end
end
