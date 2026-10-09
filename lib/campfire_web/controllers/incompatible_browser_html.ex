defmodule CampfireWeb.IncompatibleBrowserHTML do
  @moduledoc """
  The "Upgrade to a supported web browser" page (the original's `sessions/incompatible_browser`),
  rendered by `CampfireWeb.AllowBrowser`: lists the supported browsers with their minimum versions.
  """
  use CampfireWeb, :html

  import CampfireWeb.Translations, only: [translation_button: 1]

  def show(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div id="incompatible-browser" class="panel center">
        <header>
          <h1 class="txt-x-large txt-tight-lines txt-align-center margin-none-block-start margin-block-end">
            Upgrade to a supported web browser
          </h1>
          <div class="flex align-start gap">
            <.translation_button key={:incompatible_browser_messsage} />
            <p class="margin-none-block-start">
              Campfire requires a modern web browser. Please use one of the browsers listed below and make sure auto-updates are enabled.
            </p>
          </div>
        </header>

        <div class="browser-list flex align-center flex-wrap gap justify-center margin-block">
          <div
            :for={{browser, version} <- browsers()}
            id={"browser-#{browser}"}
            class="browser flex flex-column"
          >
            <img src={"/images/browsers/#{browser}.svg"} aria-hidden="true" class="center" />
            <div class="flex flex-column align-center margin-block-start-half">
              <strong>{browser |> to_string() |> String.capitalize()}</strong>
              <span>{version}+</span>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # `false` marks a browser that is unsupported at any version (IE): it isn't listed
  defp browsers do
    for {browser, version} <- CampfireWeb.BrowserSupport.versions(),
        version,
        do: {browser, version}
  end
end
