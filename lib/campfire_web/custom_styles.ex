defmodule CampfireWeb.CustomStyles do
  @moduledoc """
  The account's admin-provided CSS (`custom_styles`), injected into `<head>` by the root layout
  on every page (the original's `custom_styles_tag`).

  As a plug in the `:browser` pipeline it assigns `:custom_styles` (the sanitised CSS, or `nil`) to
  the conn. That is one primary-key read of the single account row per full page load; live
  navigation doesn't re-render the root layout, so a change applies on the next load (the editor
  does a full redirect after saving).

  The CSS is written into a `<style>` element unescaped, since HTML-escaping would break
  selectors such as `a > b`. `sanitize/1` makes sure it can't close that element or open an HTML
  comment.
  """
  @behaviour Plug

  import Plug.Conn, only: [assign: 3]

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts), do: assign(conn, :custom_styles, current())

  @doc "The sanitised custom CSS of the account, or nil when there is none."
  def current do
    case Campfire.Accounts.get_account!() do
      %{custom_styles: css} -> sanitize(css)
      nil -> nil
    end
  end

  @doc """
  Neutralises the two sequences that could break out of a `<style>` element: `</style` (any case)
  becomes `<\\/style` and `<!--` becomes `<\\!--`. In CSS a backslash escapes the next character,
  so inside strings (`content: "</style>"`) the text still means the same; elsewhere it's invalid
  CSS that the browser skips. Blank input gives nil.
  """
  @spec sanitize(String.t() | nil) :: String.t() | nil
  def sanitize(css) when is_binary(css) do
    if String.trim(css) == "" do
      nil
    else
      css
      |> String.replace(~r{</style}i, fn <<"<", rest::binary>> -> "<\\" <> rest end)
      |> String.replace("<!--", "<\\!--")
    end
  end

  def sanitize(_css), do: nil
end
