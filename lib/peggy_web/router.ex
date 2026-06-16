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
    get "/manifest.webmanifest", ManifestController, :show
    get "/locale/:locale", LocaleController, :update
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
    pipe_through [:browser, :require_authenticated_user, PeggyWeb.Plugs.AutoRouteByDevice]

    get "/view-mode", ViewModeController, :set

    live_session :require_authenticated_user,
      on_mount: [{PeggyWeb.UserAuth, :require_authenticated}, {PeggyWeb.Locale, :default}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email

      live "/farms", FarmLive.Index, :index
      live "/farms/restore", FarmLive.Restore, :show
    end

    live_session :farm_scoped,
      on_mount: [
        {PeggyWeb.UserAuth, :require_authenticated},
        {PeggyWeb.FarmScope, :require_member},
        {PeggyWeb.Locale, :default}
      ] do
      live "/farms/:farm_slug", FarmLive.Dashboard, :show
      live "/farms/:farm_slug/settings", FarmLive.Settings, :edit
      live "/farms/:farm_slug/members", MembershipLive.Index, :index
      live "/farms/:farm_slug/invite-session/:role", FarmLive.InviteSession, :show
      live "/farms/:farm_slug/locations", FarmLive.Locations, :index
      live "/farms/:farm_slug/locations/houses/:id", FarmLive.HouseDetail, :show
      live "/farms/:farm_slug/animals", FarmLive.Animals, :index
      live "/farms/:farm_slug/animals/print", FarmLive.AnimalsPrint, :show
      live "/farms/:farm_slug/animals/batch-register", FarmLive.BatchRegister, :show
      live "/farms/:farm_slug/onboarding/herd", FarmLive.HerdImport, :show
      live "/farms/:farm_slug/admin/import", FarmLive.DataImport, :show
      get "/farms/:farm_slug/admin/import/template/:type", DataImportController, :template
      live "/farms/:farm_slug/admin/backup", FarmLive.BackupRestore, :show
      get "/farms/:farm_slug/backup/download", BackupController, :download
      live "/farms/:farm_slug/animals/bulk-move", FarmLive.BulkMove, :show
      live "/farms/:farm_slug/animals/promote", FarmLive.PromoteBatches, :index
      live "/farms/:farm_slug/animals/:id", FarmLive.AnimalDetail, :show
      live "/farms/:farm_slug/animals/:id/trace", FarmLive.AnimalTrace, :show
      live "/farms/:farm_slug/animals/:id/batch-entry", FarmLive.BatchEntry, :show
      live "/farms/:farm_slug/breeding", FarmLive.Breeding, :index
      live "/farms/:farm_slug/breeding/serviceable", FarmLive.Breeding.Serviceable, :index

      live "/farms/:farm_slug/breeding/serviceable/print",
           FarmLive.Breeding.ServiceablePrint,
           :show

      live "/farms/:farm_slug/breeding/gestating", FarmLive.Breeding.Gestating, :index
      live "/farms/:farm_slug/breeding/gestating/print", FarmLive.Breeding.GestatingPrint, :show
      live "/farms/:farm_slug/breeding/lactating", FarmLive.Breeding.Lactating, :index
      live "/farms/:farm_slug/breeding/lactating/print", FarmLive.Breeding.LactatingPrint, :show
      live "/farms/:farm_slug/breeding/weaned", FarmLive.Breeding.Weaned, :index
      live "/farms/:farm_slug/breeding/deleted", FarmLive.Breeding.Deleted, :index
      live "/farms/:farm_slug/breeding/batch-service", FarmLive.BatchService, :show
      live "/farms/:farm_slug/breeding/batch-farrowing", FarmLive.BatchFarrowing, :show
      live "/farms/:farm_slug/breeding/batch-weaning", FarmLive.BatchWeaning, :show
      live "/farms/:farm_slug/breeding/close-services", FarmLive.BatchCloseServices, :show
      live "/farms/:farm_slug/reports", FarmLive.Reports, :index
      live "/farms/:farm_slug/reports/inferred", FarmLive.Reports.Inferred, :index
      live "/farms/:farm_slug/reports/performance", FarmLive.Reports.Performance, :index

      live "/farms/:farm_slug/reports/performance/print",
           FarmLive.Reports.PerformancePrint,
           :index

      get "/farms/:farm_slug/reports/export", ReportsController, :export
      live "/farms/:farm_slug/audit", FarmLive.Audit, :index

      # Mobile (phone) UI — scaffold. Same auth + farm scope as desktop.
      live "/m/:farm_slug", MobileLive.Dashboard, :show
      live "/m/:farm_slug/locations", MobileLive.Locations, :index
      live "/m/:farm_slug/animals", MobileLive.Animals, :index
      live "/m/:farm_slug/animals/promote", MobileLive.PromoteBatches, :index
      live "/m/:farm_slug/animals/:id", MobileLive.AnimalDetail, :show
      live "/m/:farm_slug/breeding/serviceable", MobileLive.Breeding.Serviceable, :index
      live "/m/:farm_slug/breeding/gestating", MobileLive.Breeding.Gestating, :index
      live "/m/:farm_slug/breeding/lactating", MobileLive.Breeding.Lactating, :index
      live "/m/:farm_slug/invite-session/:role", MobileLive.InviteSession, :show
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", PeggyWeb do
    pipe_through [:browser, PeggyWeb.Plugs.AutoRouteByDevice]

    live_session :current_user,
      on_mount: [{PeggyWeb.UserAuth, :mount_current_scope}, {PeggyWeb.Locale, :default}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
      live "/invitations/:token", InvitationLive.Show, :show
      live "/m/invitations/:token", MobileLive.InvitationShow, :show
    end

    post "/users/log-in", UserSessionController, :create
    post "/invitations/:token/accept", InvitationController, :accept
    post "/m/invitations/:token/accept", InvitationController, :mobile_accept
    delete "/users/log-out", UserSessionController, :delete
  end
end
