defmodule CampfireWeb.MessageComponents do
  @moduledoc """
  A chat message with the original Campfire markup (docs/analysis/03-ui.md §3).

  The message must have `:creator` and `boosts: [:booster]` loaded (`:room` too in search mode).
  Events (handled by the LiveView rendering the message, all with `phx-value-id` = message id):
  `boost` (+ `content`), `new_boost`, `cancel_boost`, `save_boost`, `delete_boost` (boost id),
  `reply`, `edit`, `cancel_edit`, `update_message`, `delete_message`, `play_sound` (+ `url`).
  The edit and custom boost forms submit `message_id` instead of `id`.

  Inline states come from the message's metadata (`Ash.Resource.put_metadata/3`):
  `:editing` shows the edit form instead of the body, `:boosting` shows the custom boost form.
  """
  use CampfireWeb, :html

  alias Campfire.Chat.Message
  alias CampfireWeb.{MessageBody, Paths}

  @quick_boosts ~w(👍 👏 👋 💪 ❤️ 😂 🎉 🔥)

  @doc "The quick boost emoji in the options menu."
  def quick_boosts, do: @quick_boosts

  @doc "Whether `user` may edit or delete `message` (its creator or an administrator)."
  def can_edit?(user, message) do
    message.creator_id == user.id or user.role == :administrator
  end

  attr :id, :string, required: true
  attr :message, :map, required: true
  attr :current_user, :map, required: true
  attr :users, :map, default: %{}, doc: "%{id => user}, used to render mentions"
  attr :mode, :atom, default: :room, values: [:room, :search]
  attr :highlighted, :boolean, default: false

  def message(assigns) do
    message = assigns.message

    assigns =
      assign(assigns,
        me?: message.creator_id == assigns.current_user.id,
        content_type: Message.content_type(message),
        editing?: assigns.mode == :room and metadata(message, :editing) == true,
        can_edit?: can_edit?(assigns.current_user, message),
        timestamp: DateTime.to_iso8601(message.inserted_at)
      )

    ~H"""
    <div
      id={@id}
      class={[
        "message message--formatted",
        @me? && "message--me",
        @current_user.id in (@message.mentioned_user_ids || []) && "message--mentioned",
        @content_type == :text && MessageBody.emoji_only?(@message.body) && "message--emoji",
        @highlighted && "search-highlight"
      ]}
      data-user-id={@message.creator_id}
      data-message-id={@message.id}
      data-message-timestamp={DateTime.to_unix(@message.inserted_at, :millisecond)}
      data-message-updated-at={DateTime.to_unix(@message.updated_at, :millisecond)}
    >
      <h2 class="message__day-separator">
        <time datetime={@timestamp} data-format="date"></time>
      </h2>

      <figure class="avatar message__avatar">
        <.link
          class="btn avatar"
          navigate={~p"/users/#{@message.creator_id}"}
          title={title(@message.creator)}
        >
          <img src={Paths.avatar_path(@message.creator)} width="48" height="48" aria-hidden="true" />
        </.link>
      </figure>

      <.edit_form :if={@editing?} message={@message} content_type={@content_type} />

      <div :if={!@editing?} class="message__body">
        <div class="message__body-content">
          <div class="message__meta">
            <h3 class="message__heading">
              <span class="message__author" title={title(@message.creator)}>
                <strong>{@message.creator.name}</strong>
              </span>
              <.link class="message__permalink" navigate={Paths.message_path(@message)}>
                <time class="message__timestamp" datetime={@timestamp} data-format="time"></time>
              </.link>
              <span :if={@mode == :search} class="message__room">
                <.link navigate={Paths.message_path(@message)}>{room_name(@message)}</.link>
              </span>
            </h3>

            <.actions
              :if={@mode == :room}
              message={@message}
              content_type={@content_type}
              can_edit?={@can_edit?}
            />
          </div>

          <div id={"presentation-#{@message.client_message_id}"} dir="auto">
            <.presentation message={@message} content_type={@content_type} users={@users} />
          </div>

          <.boosts
            :if={@mode == :room}
            message={@message}
            current_user={@current_user}
            boosting?={metadata(@message, :boosting) == true}
          />
        </div>
      </div>
    </div>
    """
  end

  ## Body

  attr :message, :map, required: true
  attr :content_type, :atom, required: true
  attr :users, :map, default: %{}

  defp presentation(%{content_type: :sound} = assigns) do
    name = Message.sound_name(assigns.message)
    assigns = assign(assigns, name: name, sound: Campfire.Sound.find(name))

    ~H"""
    <div class="sound">
      <button
        type="button"
        class="btn btn--plain"
        phx-click="play_sound"
        phx-value-url={Campfire.Sound.audio_path(@name)}
      >
        🔊<span class="for-screen-reader">Play {@name}</span>
      </button>
      <%= case @sound do %>
        <% {:image, file, width, height} -> %>
          <img
            src={Campfire.Sound.image_path(file)}
            width={width}
            height={height}
            class="align--middle"
            alt={@name}
          />
        <% {:text, text} -> %>
          {text}
      <% end %>
    </div>
    """
  end

  defp presentation(%{content_type: :attachment} = assigns) do
    assigns = assign(assigns, url: ~p"/attachments/#{assigns.message.id}")

    ~H"""
    <%= case media_kind(@message.attachment_content_type) do %>
      <% :image -> %>
        <div class="max-inline-size center flex overflow-clip">
          <a
            class="flex"
            href={@url}
            data-lightbox
            data-lightbox-download={@url <> "?download=1"}
            title={@message.attachment_filename}
          >
            <%!-- No stored dimensions: a fixed height keeps the layout (and scroll) from jumping on load --%>
            <img
              src={@url}
              class="message__attachment"
              style="block-size: min(20rem, 40vh); inline-size: auto; min-inline-size: 4rem; max-inline-size: 100%; object-fit: contain"
              loading="lazy"
              alt={@message.attachment_filename}
            />
          </a>
        </div>
      <% :video -> %>
        <video src={@url} class="message__attachment max-inline-size" controls preload="metadata"></video>
      <% :other -> %>
        <div class="flex-inline align-center gap-half pad-inline pad-block-half">
          <img
            src={~p"/images/common-file-text.svg"}
            width="22"
            height="22"
            class="colorize--black"
            aria-hidden="true"
          />
          <span class="overflow-ellipsis">{@message.attachment_filename}</span>
          <a class="btn btn--plain" href={@url <> "?download=1"} download>
            <img src={~p"/images/download.svg"} width="20" height="20" aria-hidden="true" />
            <span class="for-screen-reader">Download {@message.attachment_filename}</span>
          </a>
        </div>
    <% end %>
    """
  end

  defp presentation(assigns) do
    ~H"""
    {MessageBody.to_html(@message, @users)}
    """
  end

  # Only types the attachment controller serves inline can be embedded (e.g. not SVG)
  defp media_kind(content_type) do
    content_type = Campfire.Uploads.normalize_content_type(content_type)

    cond do
      not CampfireWeb.AttachmentController.inline_type?(content_type) -> :other
      String.starts_with?(content_type, "image/") -> :image
      String.starts_with?(content_type, "video/") -> :video
      true -> :other
    end
  end

  ## Boosts

  attr :message, :map, required: true
  attr :current_user, :map, required: true
  attr :boosting?, :boolean, default: false

  defp boosts(assigns) do
    ~H"""
    <div
      :if={@message.boosts != [] or @boosting?}
      class="boosts flex flex-wrap align-center gap full-width"
      style="--column-gap: 0.4ch; --row-gap: 0"
    >
      <div class="flex-inline flex-wrap gap" id={"boosts-#{@message.client_message_id}"}>
        <div
          :for={boost <- @message.boosts}
          id={"boost-#{boost.id}"}
          class="boost boost-item flex-inline max-width align-center fill-white gap"
        >
          <figure class="avatar boost__avatar flex-item-no-shrink">
            <.link
              class="btn avatar"
              navigate={~p"/users/#{boost.booster_id}"}
              title={"#{boost.booster.name} boosted #{boost.content}"}
            >
              <img src={Paths.avatar_path(boost.booster)} width="48" height="48" aria-hidden="true" />
            </.link>
          </figure>
          <span
            role="button"
            class={["txt-small", MessageBody.emoji_only?(boost.content) && "txt-medium"]}
            phx-click={
              boost.booster_id == @current_user.id &&
                JS.toggle_class("expanded", to: "#boost-#{boost.id}")
            }
          >
            {boost.content}
          </span>
          <button
            :if={boost.booster_id == @current_user.id}
            type="button"
            class="btn btn--negative flex-item-justify-end boost__delete"
            phx-click="delete_boost"
            phx-value-id={boost.id}
          >
            <img src={~p"/images/minus.svg"} width="20" height="20" aria-hidden="true" />
            <span class="for-screen-reader">Delete this boost</span>
          </button>
        </div>
      </div>

      <.boost_form :if={@boosting?} message={@message} current_user={@current_user} />

      <div :if={!@boosting?} class="flex-inline message__boost-inline">
        <button
          type="button"
          class="boost__action txt-small btn"
          phx-click="new_boost"
          phx-value-id={@message.id}
        >
          <img src={~p"/images/boost.svg"} width="20" height="20" aria-hidden="true" />
          <span class="for-screen-reader">Add a boost</span>
        </button>
      </div>
    </div>
    """
  end

  attr :message, :map, required: true
  attr :current_user, :map, required: true

  defp boost_form(assigns) do
    ~H"""
    <div class="boost flex-inline max-width fill-white" style="--column-gap: var(--inline-space-half)">
      <form
        id={"boost-form-#{@message.client_message_id}"}
        class="boost__form flex align-center gap expanded"
        phx-submit="save_boost"
        phx-window-keydown="cancel_boost"
        phx-key="Escape"
        phx-value-id={@message.id}
      >
        <input type="hidden" name="message_id" value={@message.id} />
        <label class="boost__form-label flex gap" style="--column-gap: 0.7ch;">
          <figure class="avatar boost__avatar flex-item-no-shrink">
            <img src={Paths.avatar_path(@current_user)} width="48" height="48" aria-hidden="true" />
          </figure>
          <input
            type="text"
            name="content"
            class="input input--boost txt-small"
            maxlength="16"
            autocomplete="off"
            required
            phx-mounted={JS.focus()}
            aria-label="Boost"
          />
        </label>

        <button type="submit" class="btn btn--reversed">
          <img src={~p"/images/check.svg"} width="20" height="20" aria-hidden="true" />
          <span class="for-screen-reader">Submit</span>
        </button>

        <button
          type="button"
          class="btn btn--negative"
          phx-click="cancel_boost"
          phx-value-id={@message.id}
        >
          <img src={~p"/images/minus.svg"} width="20" height="20" aria-hidden="true" />
          <span class="for-screen-reader">Cancel</span>
        </button>
      </form>
    </div>
    """
  end

  ## Options menu

  attr :message, :map, required: true
  attr :content_type, :atom, required: true
  attr :can_edit?, :boolean, required: true

  defp actions(assigns) do
    assigns = assign(assigns, quick_boosts: @quick_boosts)

    ~H"""
    <div class="message__actions">
      <details class="position-relative" phx-click-away={JS.remove_attribute("open")}>
        <summary class="btn message__action-btn message__options-btn">
          <img
            src={~p"/images/menu-dots-horizontal.svg"}
            width="20"
            height="20"
            class="colorize--black"
            aria-hidden="true"
          />
          <span class="for-screen-reader">Message options</span>
        </summary>

        <div class="message__actions-menu border shadow">
          <div class="quick-boosts">
            <button
              :for={emoji <- @quick_boosts}
              type="button"
              class="btn message__action-btn"
              phx-click="boost"
              phx-value-id={@message.id}
              phx-value-content={emoji}
            >
              <figure class="margin-none boost-character">{emoji}</figure>
              <span class="for-screen-reader">Boost with {emoji}</span>
            </button>
            <button
              type="button"
              class="btn message__action-btn message__boost-btn"
              phx-click="new_boost"
              phx-value-id={@message.id}
            >
              <img
                src={~p"/images/boost.svg"}
                class="colorize--black"
                width="20"
                height="20"
                aria-hidden="true"
              />
              <span class="for-screen-reader">New boost</span>
            </button>
          </div>

          <div class="flex flex-wrap border-top margin-block-start-half pad-block-start-half message__actions-grid">
            <a
              :if={@content_type == :attachment}
              class="btn message__action-btn center full-width"
              href={~p"/attachments/#{@message.id}?download=1"}
              title="Download"
              aria-label="Download"
              download
            >
              <img
                src={~p"/images/download.svg"}
                class="colorize--black"
                width="20"
                height="20"
                aria-hidden="true"
              />
            </a>
            <button
              :if={@content_type != :attachment}
              type="button"
              class="btn message__action-btn center full-width"
              title="Reply"
              aria-label="Reply"
              phx-click="reply"
              phx-value-id={@message.id}
            >
              <img
                src={~p"/images/reply.svg"}
                class="colorize--black"
                width="20"
                height="20"
                aria-hidden="true"
              />
            </button>
            <button
              id={"copy-link-#{@message.client_message_id}"}
              type="button"
              class="btn message__action-btn center full-width"
              title="Copy link"
              aria-label="Copy link"
              phx-hook="Copy"
              data-copy={CampfireWeb.Endpoint.url() <> Paths.message_path(@message)}
            >
              <img
                src={~p"/images/link.svg"}
                class="colorize--black"
                width="20"
                height="20"
                aria-hidden="true"
              />
            </button>
            <button
              :if={@can_edit?}
              type="button"
              class="btn message__action-btn center full-width message__edit-btn"
              style="display: inline-flex"
              title="Edit"
              aria-label="Edit"
              phx-click="edit"
              phx-value-id={@message.id}
            >
              <img
                src={~p"/images/pencil.svg"}
                class="colorize--black"
                width="20"
                height="20"
                aria-hidden="true"
              />
            </button>
          </div>
        </div>
      </details>
    </div>
    """
  end

  ## Inline edit

  attr :message, :map, required: true
  attr :content_type, :atom, required: true

  defp edit_form(assigns) do
    ~H"""
    <div class="message__body position-relative">
      <div class="message__body-content message__body-content--editing gap">
        <%= if @content_type == :attachment do %>
          <.presentation message={@message} content_type={@content_type} />
          <div class="message__edit-btns flex align-center justify-space-between gap full-width pad-block-start-half">
            <.delete_button message={@message} />
          </div>
        <% else %>
          <div class="composer--edit">
            <form
              id={"edit-form-#{@message.client_message_id}"}
              phx-submit="update_message"
              phx-window-keydown="cancel_edit"
              phx-key="Escape"
              phx-value-id={@message.id}
            >
              <input type="hidden" name="message_id" value={@message.id} />
              <div class="full-width input input--actor min-width fill-white">
                <textarea
                  name="body"
                  class="input full-width"
                  rows="3"
                  aria-label="Edit message"
                  phx-mounted={JS.focus()}
                >{@message.body}</textarea>
              </div>

              <div class="message__edit-btns flex align-center justify-space-between gap full-width pad-block-start-half">
                <button type="submit" class="btn btn--reversed">
                  <img src={~p"/images/check.svg"} width="20" height="20" aria-hidden="true" />
                  <span class="for-screen-reader">Save changes</span>
                </button>
                <.delete_button message={@message} />
              </div>
            </form>
          </div>
        <% end %>
      </div>

      <div class="message__actions flex flex-wrap">
        <button
          type="button"
          class="message__action-btn message__edit-close-btn txt-small btn btn--borderless"
          phx-click="cancel_edit"
          phx-value-id={@message.id}
        >
          <img src={~p"/images/remove.svg"} class="colorize--black" aria-hidden="true" />
          <span class="for-screen-reader">Close editor and discard changes</span>
        </button>
      </div>
    </div>
    """
  end

  attr :message, :map, required: true

  defp delete_button(assigns) do
    ~H"""
    <button
      type="button"
      class="btn btn--negative"
      phx-click="delete_message"
      phx-value-id={@message.id}
      data-confirm="Are you sure you want to delete this message?"
    >
      <img src={~p"/images/trash.svg"} width="20" height="20" aria-hidden="true" />
      <span class="for-screen-reader">Delete message</span>
    </button>
    """
  end

  ## Helpers

  defp metadata(%{__metadata__: metadata}, key), do: Map.get(metadata, key)
  defp metadata(_message, _key), do: nil

  defp title(user),
    do: [user.name, user.bio] |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join(" – ")

  defp room_name(%{room: %{name: name}}) when is_binary(name), do: name
  defp room_name(%{room: %{kind: :direct}}), do: "Ping"
  defp room_name(_), do: ""
end
