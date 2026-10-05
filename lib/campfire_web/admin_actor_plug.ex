defmodule CampfireWeb.AdminActorPlug do
  @moduledoc """
  Makes AshAdmin act as the signed-in administrator instead of its cookie-based actor picker.

  Wired through `config :ash_admin, actor_plug: CampfireWeb.AdminActorPlug`. The `/admin` live session
  runs `{CampfireWeb.UserAuth, :ensure_admin}` first, which assigns `:current_user`; that user becomes the
  actor and Ash policies are enforced (the sidebar toggle can still bypass authorization).
  """
  @behaviour AshAdmin.ActorPlug

  alias Campfire.Accounts

  @impl true
  def set_actor_session(conn), do: conn

  @impl true
  def actor_assigns(socket, _session) do
    [
      actor: socket.assigns[:current_user],
      actor_domain: Accounts,
      actor_resources: [{Accounts, Accounts.User}],
      actor_paused: false,
      actor_tenant: nil,
      authorizing: true,
      tenant: nil
    ]
  end
end
