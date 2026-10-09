defmodule CampfireWeb.AllowBrowser do
  @moduledoc """
  Plug (in the `:browser` pipeline) that answers browsers older than the supported minimums with
  the "Upgrade to a supported web browser" page instead of the app (the original's `AllowBrowser`
  concern). The decision is `CampfireWeb.BrowserSupport.blocked?/1`; requests without a
  `User-Agent`, bots and unlisted browsers pass.

  The page is rendered with status 200, like the original's `render template:` block. LiveView
  websockets aren't gated: a browser that can't load the page never connects.
  """
  @behaviour Plug

  import Plug.Conn
  import Phoenix.Controller, only: [put_layout: 2, put_view: 2, render: 3]

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    user_agent = conn |> get_req_header("user-agent") |> List.first()

    if CampfireWeb.BrowserSupport.blocked?(user_agent) do
      conn
      |> put_layout(false)
      |> put_view(html: CampfireWeb.IncompatibleBrowserHTML)
      |> render(:show, page_title: "Unsupported browser", flash: %{})
      |> halt()
    else
      conn
    end
  end
end
