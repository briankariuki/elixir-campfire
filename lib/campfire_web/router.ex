defmodule CampfireWeb.Router do
  use CampfireWeb, :router

  import CampfireWeb.UserAuth
  import AshAdmin.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CampfireWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :block_banned_ip
    plug :fetch_current_user
  end

  pipeline :bot_api do
    plug :accepts, ["json"]
    plug :block_banned_ip
  end

  scope "/", CampfireWeb do
    get "/up", HealthController, :show
  end

  ## Guests only (B1)
  scope "/", CampfireWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/first_run", FirstRunController, :new
    post "/first_run", FirstRunController, :create
    get "/session/new", SessionController, :new
    post "/session", SessionController, :create
    get "/join/:join_code", JoinController, :new
    post "/join/:join_code", JoinController, :create
  end

  ## Public (B1)
  scope "/", CampfireWeb do
    pipe_through :browser

    get "/session/transfers/:token", SessionTransferController, :show
    put "/session/transfers/:token", SessionTransferController, :update
    get "/account/logo", AccountLogoController, :show
  end

  ## Signed-in controllers
  scope "/", CampfireWeb do
    pipe_through [:browser, :require_authenticated_user]

    # B1
    delete "/session", SessionController, :delete
    get "/users/:id/avatar", AvatarController, :show

    # B2
    get "/attachments/:message_id", AttachmentController, :show
  end

  ## Signed-in LiveViews
  live_session :authenticated,
    on_mount: [{CampfireWeb.UserAuth, :ensure_authenticated}, CampfireWeb.BodyClass] do
    scope "/", CampfireWeb do
      pipe_through [:browser, :require_authenticated_user]

      # B2: chat
      live "/", HomeLive
      live "/rooms/new/open", RoomFormLive, :new_open
      live "/rooms/new/closed", RoomFormLive, :new_closed
      live "/rooms/:id", RoomLive, :show
      live "/rooms/:id/@:message_id", RoomLive, :at_message
      live "/rooms/:id/edit", RoomFormLive, :edit
      live "/directs/new", DirectPickerLive
      live "/searches", SearchLive

      # B1: people and settings
      live "/users/:id", UserLive
      live "/profile", ProfileLive
      live "/account", AccountLive
    end
  end

  ## Admin LiveViews (B1)
  live_session :admin,
    on_mount: [{CampfireWeb.UserAuth, :ensure_admin}, CampfireWeb.BodyClass] do
    scope "/account", CampfireWeb do
      pipe_through [:browser, :require_authenticated_user]

      live "/bots", BotsLive, :index
      live "/bots/new", BotsLive, :new
      live "/bots/:id/edit", BotsLive, :edit
    end
  end

  ## AshAdmin ops UI (administrators only; the actor is the signed-in admin, see CampfireWeb.AdminActorPlug)
  scope "/" do
    pipe_through [:browser, :require_authenticated_user, :require_admin]

    ash_admin "/admin",
      on_mount: [{CampfireWeb.UserAuth, :ensure_admin}],
      live_session_name: :ash_admin
  end

  ## Bot API (B1)
  scope "/rooms/:room_id/:bot_key", CampfireWeb do
    pipe_through :bot_api

    get "/messages", BotMessageController, :index
    post "/messages", BotMessageController, :create
    patch "/messages/:id", BotMessageController, :update
    put "/messages/:id", BotMessageController, :update
    delete "/messages/:id", BotMessageController, :delete
    post "/messages/:message_id/boosts", BotBoostController, :create
    delete "/messages/:message_id/boosts/:id", BotBoostController, :delete
  end

  # Development-only routes
  if Application.compile_env(:campfire, :dev_routes) do
    scope "/dev", CampfireWeb.Dev do
      pipe_through :browser

      live "/styleguide", StyleguideLive
    end
  end
end
