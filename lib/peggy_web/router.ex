defmodule PeggyWeb.Router do
  use PeggyWeb, :router

  import PeggyWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PeggyWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
    plug PeggyWeb.Locale
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", PeggyWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", PeggyWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:peggy, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: PeggyWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", PeggyWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{PeggyWeb.UserAuth, :require_authenticated}, {PeggyWeb.Locale, :default}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email

      live "/farms", FarmLive.Index, :index
    end

    live_session :farm_scoped,
      on_mount: [
        {PeggyWeb.UserAuth, :require_authenticated},
        {PeggyWeb.FarmScope, :require_member},
        {PeggyWeb.Locale, :default}
      ] do
      live "/farms/:farm_slug", FarmLive.Dashboard, :show
      live "/farms/:farm_slug/settings", FarmLive.Settings, :edit
      live "/farms/:farm_slug/locations", FarmLive.Locations, :index
      live "/farms/:farm_slug/locations/houses/:id", FarmLive.HouseDetail, :show
      live "/farms/:farm_slug/animals", FarmLive.Animals, :index
      live "/farms/:farm_slug/animals/batch-register", FarmLive.BatchRegister, :show
      live "/farms/:farm_slug/onboarding/herd", FarmLive.HerdImport, :show
      live "/farms/:farm_slug/animals/bulk-move", FarmLive.BulkMove, :show
      live "/farms/:farm_slug/animals/:id", FarmLive.AnimalDetail, :show
      live "/farms/:farm_slug/animals/:id/batch-entry", FarmLive.BatchEntry, :show
      live "/farms/:farm_slug/breeding", FarmLive.Breeding, :index
      live "/farms/:farm_slug/breeding/gestating", FarmLive.Breeding.Gestating, :index
      live "/farms/:farm_slug/breeding/lactating", FarmLive.Breeding.Lactating, :index
      live "/farms/:farm_slug/breeding/weaned", FarmLive.Breeding.Weaned, :index
      live "/farms/:farm_slug/breeding/deleted", FarmLive.Breeding.Deleted, :index
      live "/farms/:farm_slug/breeding/batch-service", FarmLive.BatchService, :show
      live "/farms/:farm_slug/breeding/batch-farrowing", FarmLive.BatchFarrowing, :show
      live "/farms/:farm_slug/breeding/batch-weaning", FarmLive.BatchWeaning, :show
      live "/farms/:farm_slug/reports", FarmLive.Reports, :index
      live "/farms/:farm_slug/audit", FarmLive.Audit, :index
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", PeggyWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{PeggyWeb.UserAuth, :mount_current_scope}, {PeggyWeb.Locale, :default}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
      live "/invitations/:token", InvitationLive.Show, :show
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
