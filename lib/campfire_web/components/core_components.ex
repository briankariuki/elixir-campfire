defmodule CampfireWeb.CoreComponents do
  @moduledoc """
  Core UI components, styled with Campfire's original CSS (`assets/css/campfire/*.css`).

  There is no Tailwind here: components emit the original markup and class names
  (`.btn`, `.input`, `.input--actor`, `.avatar`, `.switch`, `.flash`, ...). Icons are the original
  monochrome SVGs in `priv/static/images/`, referenced by name (`icon="search"` →
  `/images/search.svg`). See `/dev/styleguide` in development for examples.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  @doc """
  Renders a flash notice: Campfire's round badge (green check for `:info`, red alert for `:error`)
  that pops in at the top of the page and fades out after a few seconds. As in the original, the
  text is announced to screen readers and shown as a tooltip.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash id="offline" kind={:error} sticky hidden>Attempting to reconnect</.flash>
  """
  attr :id, :string, default: nil, doc: "the optional id of the flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :sticky, :boolean, default: false, doc: "don't fade out (e.g. for connection errors)"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id || "flash-#{@kind}-#{:erlang.phash2(msg)}"}
      class={["flash", @sticky && "flash--sticky"]}
      title={is_binary(msg) && msg}
      {@rest}
    >
      <div
        class="flash__inner shadow"
        style={@kind == :error && "--flash-background: var(--color-negative)"}
      >
        <img
          src={if @kind == :error, do: "/images/alert.svg", else: "/images/check.svg"}
          width="24"
          height="24"
          class="colorize--white"
          aria-hidden="true"
        />
      </div>
      <span class="for-screen-reader" role="alert" aria-atomic="true">{msg}</span>
    </div>
    """
  end

  @doc """
  Shows the flash group: the `:info` and `:error` flashes plus the LiveView connection errors.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        sticky
        phx-disconnected={show(".phx-client-error #client-error")}
        phx-connected={hide("#client-error")}
        hidden
      >
        We can't find the internet. Attempting to reconnect…
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        sticky
        phx-disconnected={show(".phx-server-error #server-error")}
        phx-connected={hide("#server-error")}
        hidden
      >
        Something went wrong! Attempting to reconnect…
      </.flash>
    </div>
    """
  end

  @doc """
  Renders a `.btn` button, or a link styled as one when `href`, `navigate` or `patch` is given.

  ## Examples

      <.button>Send</.button>
      <.button variant="reversed" type="submit">Save</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :variant, :string,
    default: nil,
    values: [nil, "reversed", "negative", "plain", "borderless", "faux"]

  attr :class, :any, default: nil
  attr :type, :string, default: nil

  attr :rest, :global,
    include: ~w(href navigate patch method download name value disabled form replace)

  slot :inner_block, required: true

  def button(assigns) do
    assigns = assign(assigns, :classes, ["btn", variant_class(assigns.variant), assigns.class])

    if link?(assigns.rest) do
      ~H"""
      <.link class={@classes} {@rest}>{render_slot(@inner_block)}</.link>
      """
    else
      ~H"""
      <button type={@type || "button"} class={@classes} {@rest}>{render_slot(@inner_block)}</button>
      """
    end
  end

  @doc """
  Renders Campfire's round icon-only button: a `.btn` holding an icon image plus a screen-reader
  label (the CSS turns any `.btn` with an `img` and `.for-screen-reader` into a circle).

  Works as a `<button>` or, with `href`/`navigate`/`patch`, as a link.

  ## Examples

      <.icon_button icon="search" label="Search" navigate={~p"/searches"} />
      <.icon_button icon="arrow-up" label="Send message" type="submit" variant="reversed" />
      <.icon_button icon="trash" label="Delete" variant="negative" phx-click="delete" data-confirm="Sure?" />
  """
  attr :icon, :string, required: true, doc: "image name in /images, without .svg"
  attr :label, :string, required: true, doc: "accessible label (visually hidden)"
  attr :size, :integer, default: 20

  attr :variant, :string,
    default: nil,
    values: [nil, "reversed", "negative", "plain", "borderless"]

  attr :class, :any, default: nil
  attr :type, :string, default: nil

  attr :rest, :global,
    include: ~w(href navigate patch method download name value disabled form replace target)

  def icon_button(assigns) do
    assigns = assign(assigns, :classes, ["btn", variant_class(assigns.variant), assigns.class])

    if link?(assigns.rest) do
      ~H"""
      <.link class={@classes} {@rest}>
        <img src={icon_path(@icon)} width={@size} height={@size} aria-hidden="true" />
        <span class="for-screen-reader">{@label}</span>
      </.link>
      """
    else
      ~H"""
      <button type={@type || "button"} class={@classes} {@rest}>
        <img src={icon_path(@icon)} width={@size} height={@size} aria-hidden="true" />
        <span class="for-screen-reader">{@label}</span>
      </button>
      """
    end
  end

  @doc """
  Renders an avatar image inside `figure.avatar` (or another tag). With `href`/`navigate` the image
  is wrapped in a `a.btn.avatar` link, like the original `avatar_tag`.

  ## Examples

      <.avatar src={~p"/users/1/avatar"} />
      <.avatar src={@url} size="2.2ch" class="boost__avatar" />
      <.avatar src={@url} class="message__avatar" navigate={~p"/users/1"} title="David – Founder" />
      <.avatar tag="span" src={@url} />
  """
  attr :src, :string, required: true
  attr :size, :string, default: nil, doc: "CSS length for --avatar-size, e.g. \"10ch\""
  attr :tag, :string, default: "figure"
  attr :class, :any, default: nil
  attr :title, :string, default: nil
  attr :alt, :string, default: ""
  attr :rest, :global, include: ~w(href navigate patch)

  def avatar(assigns) do
    ~H"""
    <.dynamic_tag
      tag_name={@tag}
      class={["avatar", @class]}
      style={@size && "--avatar-size: #{@size}"}
    >
      <%= if link?(@rest) do %>
        <.link class="btn avatar" title={@title} {@rest}>
          <img src={@src} width="48" height="48" alt={@alt} aria-hidden="true" />
        </.link>
      <% else %>
        <img src={@src} width="48" height="48" alt={@alt} title={@title} aria-hidden="true" />
      <% end %>
    </.dynamic_tag>
    """
  end

  @doc """
  Renders a toggle switch: `label.switch > input.switch__input + span.switch__btn.round`.

  A hidden `false` input is included so unchecked switches still submit a value.

  ## Examples

      <.switch name="account[restrict]" checked={@restrict?} label="Restrict room creation" />
      <.switch field={@form[:restrict]} label="Restrict" phx-click="toggle" />
  """
  attr :id, :any, default: nil
  attr :name, :any, default: nil
  attr :checked, :boolean, default: nil
  attr :value, :any, default: "true"
  attr :label, :string, required: true, doc: "accessible label (visually hidden)"
  attr :field, Phoenix.HTML.FormField, default: nil
  attr :hidden_input, :boolean, default: true, doc: "include a hidden false value"
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(disabled form)

  def switch(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    assigns
    |> assign(field: nil, id: assigns.id || field.id, name: assigns.name || field.name)
    |> assign(
      :checked,
      if(is_nil(assigns.checked),
        do: Phoenix.HTML.Form.normalize_value("checkbox", field.value),
        else: assigns.checked
      )
    )
    |> switch()
  end

  def switch(assigns) do
    ~H"""
    <label class={["switch", @class]}>
      <input
        :if={@hidden_input && @name}
        type="hidden"
        name={@name}
        value="false"
        disabled={@rest[:disabled]}
        form={@rest[:form]}
      />
      <input
        type="checkbox"
        id={@id}
        name={@name}
        value={@value}
        checked={@checked}
        class="switch__input"
        {@rest}
      />
      <span class="switch__btn round"></span>
      <span class="for-screen-reader">{@label}</span>
    </label>
    """
  end

  @doc """
  Renders a form input with Campfire's `.input` styling.

  Types: `text` (default), `email`, `password`, `search`, `url`, `number`, `textarea`, `checkbox`,
  `file` and `hidden`. Pass a `Phoenix.HTML.FormField` as `field`, or `name`/`value` directly.

  With `icon`, it renders the `input--actor` variant used across Campfire's forms: a `label` styled
  as the input, holding a bare `.input` and a trailing icon.

  ## Examples

      <.input field={@form[:email_address]} type="email" icon="email" placeholder="Email address" class="txt-large" />
      <.input field={@form[:bio]} type="textarea" rows="3" maxlength="200" />
      <.input name="q" type="search" value={@q} placeholder="Search" />
      <.input field={@form[:avatar]} type="file" icon="camera" label="Add your avatar" accept="image/*" />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any
  attr :type, :string, default: "text"
  attr :field, Phoenix.HTML.FormField, doc: "a form field struct, e.g. @form[:email]"
  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :icon, :string, default: nil, doc: "icon name; renders the input--actor variant"
  attr :class, :any, default: nil, doc: "extra classes for the outer element"
  attr :multiple, :boolean, default: false

  attr :rest, :global,
    include:
      ~w(accept autocomplete autofocus capture cols disabled form list max maxlength min
                minlength multiple pattern placeholder readonly required rows size step spellcheck)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error/1))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <label class={["flex align-center gap", @class]}>
      <input type="hidden" name={@name} value="false" disabled={@rest[:disabled]} form={@rest[:form]} />
      <input
        type="checkbox"
        id={@id}
        name={@name}
        value="true"
        checked={@checked}
        class="input-checkbox"
        {@rest}
      />
      <span :if={@label}>{@label}</span>
    </label>
    <.error :for={msg <- @errors}>{msg}</.error>
    """
  end

  def input(%{type: "file"} = assigns) do
    ~H"""
    <label class={["btn input--file", @class]}>
      <img src={icon_path(@icon || "attachment")} aria-hidden="true" />
      <input type="file" id={@id} name={@name} class="input" multiple={@multiple} {@rest} />
      <span class="for-screen-reader">{@label || "Choose a file"}</span>
    </label>
    <.error :for={msg <- @errors}>{msg}</.error>
    """
  end

  # Actor variant: the label is styled as the input and holds a bare `.input` plus an icon.
  def input(%{icon: icon} = assigns) when is_binary(icon) do
    ~H"""
    <label class={["flex align-center gap input input--actor", @class]}>
      <span :if={@label} class="for-screen-reader">{@label}</span>
      <.control type={@type} id={@id} name={@name} value={@value} rest={@rest} />
      <img src={icon_path(@icon)} width="24" height="24" class="colorize--black" aria-hidden="true" />
    </label>
    <.error :for={msg <- @errors}>{msg}</.error>
    """
  end

  def input(%{label: label} = assigns) when is_binary(label) do
    ~H"""
    <label class={["flex flex-column gap-half", @class]}>
      <strong class="txt-small">{@label}</strong>
      <.control type={@type} id={@id} name={@name} value={@value} rest={@rest} />
    </label>
    <.error :for={msg <- @errors}>{msg}</.error>
    """
  end

  def input(assigns) do
    ~H"""
    <.control type={@type} id={@id} name={@name} value={@value} class={@class} rest={@rest} />
    <.error :for={msg <- @errors}>{msg}</.error>
    """
  end

  attr :type, :string, required: true
  attr :id, :any, required: true
  attr :name, :any, required: true
  attr :value, :any, required: true
  attr :class, :any, default: nil
  attr :rest, :map, default: %{}

  defp control(%{type: "textarea"} = assigns) do
    ~H"""
    <textarea id={@id} name={@name} class={["input" | List.wrap(@class)]} {@rest}>{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
    """
  end

  defp control(assigns) do
    ~H"""
    <input
      type={@type}
      id={@id}
      name={@name}
      value={Phoenix.HTML.Form.normalize_value(@type, @value)}
      class={["input" | List.wrap(@class)]}
      {@rest}
    />
    """
  end

  @doc """
  Renders a field error message.
  """
  slot :inner_block, required: true

  def error(assigns) do
    ~H"""
    <p class="input-error">{render_slot(@inner_block)}</p>
    """
  end

  ## Helpers

  @doc "The path of a Campfire icon in `priv/static/images`, e.g. `icon_path(\"search\")`."
  def icon_path(name), do: "/images/#{name}.svg"

  defp variant_class(nil), do: nil
  defp variant_class(variant), do: "btn--#{variant}"

  defp link?(rest), do: Enum.any?([:href, :navigate, :patch], &Map.has_key?(rest, &1))

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    js
    |> JS.show(to: selector)
    |> JS.remove_attribute("hidden", to: selector)
  end

  def hide(js \\ %JS{}, selector) do
    js
    |> JS.hide(to: selector)
    |> JS.set_attribute({"hidden", ""}, to: selector)
  end

  @doc """
  Translates an error message (no gettext in this app; interpolates `%{key}` bindings).
  """
  def translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
