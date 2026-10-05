defmodule CampfireWeb.BlockedHTML do
  @moduledoc "The banned-IP page (`GET /blocked`, see `CampfireWeb.BlockedController`)."
  use CampfireWeb, :html

  def show(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section id="blocked" class="panel txt-align-center flex flex-column gap">
        <h1 class="txt-large margin-none">Campfire is unavailable from this network</h1>
        <p class="margin-none">Requests from your IP address have been blocked.</p>
        <a id="blocked-retry" href={~p"/"} class="btn center">Try again</a>
      </section>
    </Layouts.app>
    """
  end
end
