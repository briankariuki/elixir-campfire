defmodule CampfireWeb.RoomComponents do
  @moduledoc """
  Pieces of the room page that depend on the account: the logo in the nav and the system welcome
  card of the original room (`rooms/show/_nav`, `rooms/show/_invitation` in docs/analysis/03-ui.md
  §1.5).
  """
  use CampfireWeb, :html

  import CampfireWeb.SettingsComponents, only: [invite: 1]

  alias Campfire.{Accounts, Chat}
  alias Campfire.Chat.Message
  alias CampfireWeb.Paths

  @page_size Message.page_size()

  @doc """
  Assigns for a room page: `:account`, `:invite_url`, `:original_room?` (the room is the oldest one
  the user has, which is the account's first room "All Talk" for every member) and `:body_class`
  (with `account-has-logo` when the account has a logo).
  """
  def room_assigns(room, user) do
    account = Accounts.get_account!()

    original? =
      match?({:ok, %{id: id}} when id == room.id, Chat.oldest_room(actor: user)) and
        room.kind == :open

    [
      account: account,
      invite_url: account && url(~p"/join/#{account.join_code}"),
      original_room?: original?,
      body_class: body_class(account)
    ]
  end

  defp body_class(%{logo_key: key}) when is_binary(key), do: "sidebar account-has-logo"
  defp body_class(_account), do: "sidebar"

  @doc """
  Whether to show the system welcome card: the original room, while all its messages fit in one
  page (the original's `!messages.paged?`).
  """
  def show_welcome?(original_room?, account, more_older?, more_newer?, loaded_ids) do
    original_room? and not is_nil(account) and not more_older? and not more_newer? and
      length(loaded_ids) < @page_size
  end

  attr :account, :any, default: nil, doc: "the account; the logo is shown only when it has one"

  def nav_logo(%{account: %{logo_key: key}} = assigns) when is_binary(key) do
    ~H"""
    <figure class="account-logo avatar">
      <img src={Paths.logo_path(@account)} alt="Account logo" width="300" height="300" />
    </figure>
    """
  end

  def nav_logo(assigns), do: ~H""

  attr :account, :map, required: true
  attr :invite_url, :string, required: true

  def system_welcome(assigns) do
    ~H"""
    <div id="system_welcome" class="message message--formatted txt-align-center center">
      <div class="message__body center">
        <div class="message__body-content position-relative">
          <figure class="account-logo avatar center margin-block-end txt-large">
            <img src={Paths.logo_path(@account)} alt="Account logo" width="300" height="300" />
          </figure>
          <p>
            <strong>Welcome to Campfire</strong><br />
            To invite people to chat, share the join link below.
          </p>
          <.invite url={@invite_url} />
        </div>
      </div>
    </div>
    """
  end
end
