defmodule CampfireWeb.BodyClass do
  @moduledoc """
  Keeps `<body class>` in sync with the LiveView that is on screen.

  The root layout renders the `:body_class` assign on the first request, but live navigation
  inside a `live_session` never re-renders the root layout. Without this hook a chat page's
  `"sidebar"` class sticks to the panel pages (`/profile`, `/users/:id`, `/account`), which
  bottom-justifies `#main-content` and makes the top of a tall panel unreachable.

  Attached as an `on_mount` hook, it pushes the class on every `handle_params` (the initial
  mount and every later navigation); `app.js` applies it to `<body>`.
  """
  import Phoenix.LiveView

  def on_mount(:default, _params, _session, socket) do
    {:cont, attach_hook(socket, :set_body_class, :handle_params, &push_body_class/3)}
  end

  defp push_body_class(_params, _uri, socket) do
    {:cont, push_event(socket, "body-class", %{class: socket.assigns[:body_class] || ""})}
  end
end
