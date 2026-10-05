defmodule CampfireWeb.PageController do
  use CampfireWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
