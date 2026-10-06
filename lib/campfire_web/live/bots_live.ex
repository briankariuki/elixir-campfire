defmodule CampfireWeb.BotsLive do
  @moduledoc """
  Admin-only chat bot management (`/account/bots`): the list with per-room `curl` examples, and
  the new/edit form (avatar, name, webhook URL). Edit also deletes the bot or regenerates its key.
  """
  use CampfireWeb, :live_view

  import CampfireWeb.Translations, only: [translation_button: 1]

  alias Campfire.Accounts
  alias Campfire.Accounts.User
  alias CampfireWeb.{ErrorMessages, ImageUpload, Paths}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     allow_upload(socket, :avatar,
       accept: ImageUpload.accept(),
       max_entries: 1,
       max_file_size: 10_000_000
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    me = socket.assigns.current_user

    bots =
      Accounts.list_bots!(actor: me, load: [:rooms])
      |> Enum.map(fn bot ->
        rooms =
          bot.rooms
          |> Enum.reject(&(&1.kind == :direct))
          |> Enum.sort_by(&String.downcase(&1.name || ""))

        %{bot: bot, rooms: rooms}
      end)

    assign(socket, page_title: "Chat bots", bots: bots, bot: nil, form: nil)
  end

  defp apply_action(socket, :new, _params) do
    form =
      User
      |> AshPhoenix.Form.for_create(:create_bot, actor: socket.assigns.current_user, as: "bot")
      |> to_form()

    assign(socket, page_title: "New chat bot", bot: nil, form: form)
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    me = socket.assigns.current_user

    case Enum.find(Accounts.list_bots!(actor: me), &(to_string(&1.id) == id)) do
      nil ->
        socket
        |> put_flash(:error, "Bot not found")
        |> push_navigate(to: ~p"/account/bots")

      bot ->
        assign(socket, page_title: "Edit bot", bot: bot, form: edit_form(bot, me))
    end
  end

  defp edit_form(bot, actor) do
    bot
    |> AshPhoenix.Form.for_update(:update_bot,
      actor: actor,
      as: "bot",
      params: %{"name" => bot.name, "webhook_url" => bot.webhook && bot.webhook.url}
    )
    |> to_form()
  end

  @impl true
  def handle_event("validate", %{"bot" => params}, socket) do
    {:noreply, assign(socket, form: AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("save", %{"bot" => params}, socket) do
    avatar_key = store_avatar(socket)
    params = if avatar_key, do: Map.put(params, "avatar_key", avatar_key), else: params

    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, _bot} ->
        {:noreply,
         socket
         |> put_flash(:info, "Saved")
         |> push_navigate(to: ~p"/account/bots")}

      {:error, form} ->
        Campfire.Uploads.delete(avatar_key)
        {:noreply, assign(socket, form: form)}
    end
  end

  def handle_event("delete", _params, socket) do
    case Accounts.deactivate_user(socket.assigns.bot, actor: socket.assigns.current_user) do
      {:ok, _} ->
        {:noreply,
         socket |> put_flash(:info, "Bot removed") |> push_navigate(to: ~p"/account/bots")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, ErrorMessages.summary(error))}
    end
  end

  def handle_event("reset_key", _params, socket) do
    case Accounts.reset_bot_key(socket.assigns.bot, actor: socket.assigns.current_user) do
      {:ok, bot} ->
        {:noreply,
         socket
         |> assign(bot: %{socket.assigns.bot | bot_token: bot.bot_token})
         |> put_flash(:info, "A new key was generated")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, ErrorMessages.summary(error))}
    end
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :avatar, ref)}
  end

  defp store_avatar(socket) do
    socket
    |> consume_uploaded_entries(:avatar, fn %{path: path}, entry ->
      {:ok, ImageUpload.store(path, entry.client_name, entry.client_type)}
    end)
    |> List.first()
  end

  @impl true
  def render(%{live_action: :index} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <:nav>
        <CampfireWeb.SettingsComponents.back_button to={~p"/account"} />
      </:nav>

      <section class="panel panel--wide txt-align-center flex flex-column position-relative">
        <div class="flex align-center gap">
          <div class="panel__button">
            <.translation_button key={:chat_bots} />
          </div>
          <div class="pad-inline-double center">
            <h1 class="margin-none">Chat bots</h1>
            <p class="margin-none-block-start">
              With Chat bots, other sites and services can post updates directly to Campfire.
            </p>

            <.link
              navigate={~p"/account/bots/new"}
              class="btn btn--reversed txt-large"
              aria-label="Add a chat bot"
            >
              <img src={~p"/images/bot.svg"} width="20" height="20" aria-hidden="true" />
              <img src={~p"/images/add.svg"} width="20" height="20" aria-hidden="true" />
            </.link>
          </div>
        </div>

        <div class="pad-inline pad-block-start">
          <menu id="bots" class="flex flex-column gap margin-none pad">
            <.bot_item :for={%{bot: bot, rooms: rooms} <- @bots} bot={bot} rooms={rooms} />
          </menu>
        </div>
      </section>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <:nav>
        <CampfireWeb.SettingsComponents.back_button to={~p"/account/bots"} />
      </:nav>

      <section class="panel">
        <.form
          for={@form}
          id="bot-form"
          phx-change="validate"
          phx-submit="save"
          class="flex flex-column gap"
        >
          <h1 class="for-screen-reader">Chat Bot Setup</h1>

          <div class="align-center center avatar__form gap">
            <label class="btn input--file">
              <img src={~p"/images/camera.svg"} width="20" height="20" aria-hidden="true" />
              <.live_file_input upload={@uploads.avatar} class="input" />
              <span class="for-screen-reader">Upload bot avatar</span>
            </label>

            <div class="avatar input--file txt-xx-large" style="--avatar-size: var(--btn-size);">
              <%= case @uploads.avatar.entries do %>
                <% [entry | _] -> %>
                  <.live_img_preview entry={entry} width="48" height="48" />
                <% [] -> %>
                  <img src={bot_avatar(@bot)} alt="Bot avatar" width="48" height="48" />
              <% end %>
            </div>
          </div>

          <div class="flex align-center gap">
            <.translation_button key={:bot_name} />
            <.input
              field={@form[:name]}
              icon="bot"
              label="Name"
              class="txt-large flex-item-grow"
              placeholder="Name the bot"
              autocomplete="off"
              required
            />
          </div>
          <div class="flex align-center gap">
            <.translation_button key={:webhook_url} />
            <.input
              field={@form[:webhook_url]}
              type="url"
              icon="web"
              label="Webhook URL"
              class="txt-large flex-item-grow"
              placeholder="Webhook URL"
            />
          </div>

          <.icon_button
            icon="check"
            label="Save changes"
            type="submit"
            variant="reversed"
            class="center txt-large"
          />
        </.form>

        <%= if @bot do %>
          <hr class="separator full-width margin-block-double" />

          <div class="flex align-center gap justify-space-between">
            <.button
              id="delete-bot"
              variant="negative"
              class="txt--small"
              aria-label="Delete this chat bot"
              phx-click="delete"
              data-confirm="Are you sure you want to permanently remove this bot from the account? This can’t be undone."
            >
              <img src={~p"/images/trash.svg"} width="20" height="20" aria-hidden="true" />
              <img src={~p"/images/bot.svg"} width="20" height="20" aria-hidden="true" />
            </.button>

            <.button
              id="reset-bot-key"
              variant="negative"
              class="full-width txt--small"
              aria-label="Generate a new key"
              phx-click="reset_key"
              data-confirm="Are you sure you want to change the bot key? All usage of this bot must be updated."
            >
              <img src={~p"/images/refresh.svg"} width="20" height="20" aria-hidden="true" />
              <img src={~p"/images/key.svg"} width="20" height="20" aria-hidden="true" />
            </.button>
          </div>
        <% end %>
      </section>
    </Layouts.app>
    """
  end

  attr :bot, :map, required: true
  attr :rooms, :list, required: true

  defp bot_item(assigns) do
    ~H"""
    <li
      id={"bot-#{@bot.id}"}
      class="flex flex-column gap flush fill-shade border-radius pad-block pad-inline-double"
    >
      <div class="flex align-center gap">
        <figure class="avatar flex-item-no-shrink" style="--avatar-size: 2.65em;">
          <img src={Paths.avatar_path(@bot)} width="48" height="48" loading="lazy" aria-hidden="true" />
        </figure>

        <div class="min-width">
          <div class="overflow-ellipsis txt-large"><strong>{@bot.name}</strong></div>
        </div>

        <.icon_button
          icon="pencil"
          label={"Edit #{@bot.name}"}
          class="flex-item-justify-end"
          navigate={~p"/account/bots/#{@bot.id}/edit"}
        />
      </div>

      <fieldset :for={room <- @rooms} class="gap max-width pad border border-radius">
        <legend class="min-width txt-align-start pad-inline">
          <strong class="overflow-ellipsis">{room.name}</strong>
        </legend>

        <.curl_line
          id={"curl-message-#{@bot.id}-#{room.id}"}
          icon="messages-outlined"
          label="curl command for posting messages"
          text={"curl -d 'Hello!' #{messages_url(@bot, room)}"}
        />
        <.curl_line
          id={"curl-attachment-#{@bot.id}-#{room.id}"}
          icon="attachment"
          label="curl command for posting attachments"
          text={~s(curl -F "attachment=@/path/to/file" #{messages_url(@bot, room)})}
        />
      </fieldset>
    </li>
    """
  end

  attr :id, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :text, :string, required: true

  defp curl_line(assigns) do
    ~H"""
    <div class="flex align-center gap">
      <img
        src={"/images/#{@icon}.svg"}
        width="24"
        height="24"
        class="colorize--black"
        aria-hidden="true"
      />

      <div class="flex-item-grow">
        <input
          type="text"
          class="input full-width fill-white"
          value={@text}
          aria-label={@label}
          readonly
        />
      </div>

      <div class="txt-small">
        <CampfireWeb.SettingsComponents.copy_button id={@id} text={@text} label={"Copy: #{@label}"} />
      </div>
    </div>
    """
  end

  defp messages_url(bot, room), do: url(~p"/rooms/#{room.id}/#{User.bot_key(bot)}/messages")

  defp bot_avatar(%User{avatar_key: key} = bot) when is_binary(key), do: Paths.avatar_path(bot)
  defp bot_avatar(_bot), do: ~p"/images/default-bot-avatar.svg"
end
