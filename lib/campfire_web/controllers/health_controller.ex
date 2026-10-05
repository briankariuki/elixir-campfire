defmodule CampfireWeb.HealthController do
  use CampfireWeb, :controller

  def show(conn, _params), do: send_resp(conn, 200, "OK")
end
