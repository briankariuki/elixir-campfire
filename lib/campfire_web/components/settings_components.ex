defmodule CampfireWeb.SettingsComponents do
  @moduledoc """
  Pieces shared by the people and settings pages (profile, user, account, bots): the back button,
  copy-to-clipboard buttons, the session transfer widget, the invite link and the involvement bell.
  """
  use CampfireWeb, :html

  alias Campfire.Chat.Room

  @doc "The round back button for `<:nav>`."
  attr :to, :string, default: "/"

  def back_button(assigns) do
    ~H"""
    <div class="flex-item-justify-start">
      <.icon_button icon="arrow-left" label="Go Back" navigate={@to} />
    </div>
    """
  end

  @doc "A round button copying `text` to the clipboard (the `Copy` hook)."
  attr :id, :string, required: true
  attr :text, :string, required: true
  attr :label, :string, required: true

  def copy_button(assigns) do
    ~H"""
    <button type="button" id={@id} class="btn" phx-hook="Copy" data-copy={@text}>
      <img
        src={~p"/images/copy-paste.svg"}
        width="20"
        height="20"
        class="flex-item-no-shrink colorize--black"
        aria-hidden="true"
      />
      <span class="for-screen-reader">{@label}</span>
    </button>
    """
  end

  @doc """
  A round button showing the QR code of `url` in the lightbox (the original's `link_to_zoom_qr_code`).

  The SVG is a `data:` URI (`CampfireWeb.QRCode`), so there is no QR endpoint. The click is handled
  by the `Lightbox` hook of an ancestor (`a[data-lightbox]`).
  """
  attr :id, :string, required: true
  attr :url, :string, required: true
  attr :label, :string, required: true

  def qr_button(assigns) do
    assigns = assign(assigns, :qr, CampfireWeb.QRCode.data_uri(assigns.url))

    ~H"""
    <a id={@id} href={@qr} class="btn" data-lightbox data-lightbox-download={@qr}>
      <span class="for-screen-reader">{@label}</span>
      <img
        src={~p"/images/qr-code.svg"}
        width="20"
        height="20"
        class="colorize--black"
        aria-hidden="true"
      />
    </a>
    """
  end

  @doc "The session transfer link of `user` (own profile, or an admin helping a user)."
  attr :user, :map, required: true
  attr :current_user, :map, required: true

  def transfer_link(assigns) do
    assigns = assign(assigns, :url, CampfireWeb.Transfer.url(assigns.user))

    ~H"""
    <fieldset id="transfer-link" phx-hook="Lightbox">
      <legend class="gap">
        <img
          :for={icon <- ~w(laptop transfer mobile-phone)}
          src={"/images/#{icon}.svg"}
          width="36"
          height="36"
          class="colorize--black"
          aria-hidden="true"
        />
      </legend>

      <div class="flex flex-column gap">
        <%= if @current_user.id != @user.id do %>
          <div class="flex align-center gap justify-center">
            <img
              src={~p"/images/crown.svg"}
              width="16"
              height="16"
              class="flex-item-no-shrink colorize--black"
              aria-hidden="true"
            />
            <label for="session_transfer_url">Share to get them back into their account</label>
          </div>
        <% else %>
          <label for="session_transfer_url" class="for-screen-reader">
            Use this link to login automatically on another device
          </label>
        <% end %>

        <input type="text" class="input" value={@url} id="session_transfer_url" readonly />

        <div class="flex align-center center gap">
          <.qr_button id="qr-transfer-url" url={@url} label="Show auto-login QR code" />
          <.copy_button id="copy-transfer-url" text={@url} label="Copy auto-login link" />
        </div>
      </div>
    </fieldset>
    """
  end

  @doc "The invite link widget (`accounts/_invite`): the link, QR code and copy buttons, and a regenerate button for admins."
  attr :url, :string, required: true
  attr :admin, :boolean, default: false

  attr :lightbox, :boolean,
    default: true,
    doc:
      "mount the `Lightbox` hook for the QR button; pass false inside a page that already has one (the room's message area)"

  def invite(assigns) do
    ~H"""
    <div
      id="invite"
      class="flex flex-column align-center gap"
      phx-hook={@lightbox && "Lightbox"}
    >
      <label class="flex flex-column gap full-width" style="--row-gap: 0.5em">
        <strong id="invite_label" class="invite-label">Share to invite more people</strong>
        <span class="flex align-center gap input input--actor fill-white">
          <img
            src={~p"/images/person-add.svg"}
            width="20"
            height="20"
            class="colorize--black"
            aria-hidden="true"
          />
          <input
            type="text"
            class="input"
            id="invite_url"
            value={@url}
            aria-labelledby="invite_label"
            readonly
          />
        </span>
      </label>

      <div class="flex align-center gap">
        <.qr_button id="qr-invite-url" url={@url} label="Show join link QR code" />
        <.copy_button id="copy-invite-url" text={@url} label="Copy join link" />

        <button
          :if={@admin}
          type="button"
          id="regenerate-join-code"
          class="btn btn--regenerate"
          phx-click="regenerate_join_code"
          data-confirm="Are you sure you want to change the join link? The current link will stop working."
        >
          <img
            src={~p"/images/refresh.svg"}
            width="20"
            height="20"
            class="colorize--black"
            aria-hidden="true"
          />
          <span class="for-screen-reader">Regenerate join link</span>
        </button>
      </div>
    </div>
    """
  end

  @involvement_labels %{
    mentions: "Notifying about @ mentions",
    everything: "Notifying about all messages",
    nothing: "Notifications are off",
    invisible: "Notifications are off and room invisible in sidebar"
  }

  @shared_order [:mentions, :everything, :nothing, :invisible]
  @direct_order [:everything, :nothing]

  @doc """
  The involvement bell: clicking sends `event` with `phx-value-id={membership.id}`. The server
  cycles with `next_involvement/2`.
  """
  attr :membership, :map, required: true, doc: "a membership with `:room` loaded"
  attr :event, :string, default: "cycle_involvement"

  def involvement_button(assigns) do
    assigns = assign(assigns, :label, @involvement_labels[assigns.membership.involvement])

    ~H"""
    <button
      type="button"
      id={"involvement-#{@membership.id}"}
      class={["btn", @membership.involvement]}
      role="checkbox"
      aria-checked="true"
      aria-labelledby={"involvement-label-#{@membership.id}"}
      phx-click={@event}
      phx-value-id={@membership.id}
    >
      <img
        src={"/images/notification-bell-#{@membership.involvement}.svg"}
        width="20"
        height="20"
        aria-hidden="true"
      />
      <span class="for-screen-reader" id={"involvement-label-#{@membership.id}"}>{@label}</span>
    </button>
    """
  end

  @doc """
  The involvement after `current` for a room: shared rooms cycle
  mentions → everything → nothing → invisible; direct rooms toggle everything ↔ nothing.
  """
  def next_involvement(%Room{kind: :direct}, current), do: next_in(@direct_order, current)
  def next_involvement(_room, current), do: next_in(@shared_order, current)

  defp next_in(order, current) do
    case Enum.drop_while(order, &(&1 != current)) do
      [_, next | _] -> next
      _ -> hd(order)
    end
  end

  @doc "A room's display name: its name, or the other members' names for a direct room."
  def room_name(%Room{kind: :direct, users: users}, current_user) when is_list(users) do
    case Enum.reject(users, &(&1.id == current_user.id)) do
      [] -> current_user.name
      others -> others |> Enum.map(& &1.name) |> Enum.sort() |> Enum.join(", ")
    end
  end

  def room_name(%Room{name: name}, _current_user), do: name
end
