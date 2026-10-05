defmodule CampfireWeb.PageControllerTest do
  use CampfireWeb.ConnCase

  test "GET / renders the Campfire layout", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ ~r/<nav[^>]* id="nav"/
    assert html =~ ~r/<main[^>]* id="main-content"/
    assert html =~ ~s(<dialog class="lightbox")
    assert html =~ "/assets/css/app.css"
  end
end
