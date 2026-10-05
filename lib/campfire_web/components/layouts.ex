defmodule CampfireWeb.Layouts do
  @moduledoc """
  Campfire's page skeleton.

  The root layout (`layouts/root.html.heex`) renders `<head>`, `<body class={@body_class}>`, the
  skip-navigation link and the global lightbox `<dialog>`. Set the `:body_class` assign
  (e.g. `"sidebar"`, `"signup"`, `"sidebar searches"`) in a LiveView's `mount/3` or a controller.

  `app/1` renders the grid areas styled by `layout.css`: `#nav`, the flash, `#main-content` (with
  `#footer` inside it) and `#sidebar`.
  """
  use CampfireWeb, :html

  embed_templates "layouts/*"

  @doc """
  Renders the app layout.

  ## Examples

      <Layouts.app flash={@flash} current_user={@current_user}>
        <:nav>
          <span class="btn btn--reversed btn--faux room--current">
            <h1 class="room__contents txt-medium overflow-ellipsis">Watercooler</h1>
          </span>
        </:nav>

        <div id="message-area" class="message-area">…</div>

        <:footer>…composer…</:footer>
        <:sidebar>…rooms…</:sidebar>
      </Layouts.app>
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current_user, :any, default: nil, doc: "the signed-in user, if any"

  slot :nav, doc: "the top bar (#nav)"
  slot :inner_block, required: true
  slot :footer, doc: "rendered as <footer id=\"footer\"> at the bottom of #main-content"
  slot :sidebar, doc: "rendered as <aside id=\"sidebar\">"

  def app(assigns) do
    ~H"""
    <nav id="nav">{render_slot(@nav)}</nav>

    <.flash_group flash={@flash} />

    <main id="main-content" phx-hook="LocalTime">
      {render_slot(@inner_block)}

      <footer id="footer">{render_slot(@footer)}</footer>
    </main>

    <aside id="sidebar">{render_slot(@sidebar)}</aside>
    """
  end
end
