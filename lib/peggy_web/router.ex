defmodule PeggyWeb.Router do
  use PeggyWeb, :router

  import PeggyWeb.UserAuth
  import PeggyWeb.Locale
  import PeggyWeb.ActiveFarm

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {PeggyWeb.LayoutView, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
    plug :set_locale
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", PeggyWeb do
    pipe_through :browser
    get "/", WelcomeController, :index
  end

  # Other scopes may use custom stacks.
  # scope "/api", PeggyWeb do
  #   pipe_through :api
  # end

  # Enables LiveDashboard only for development
  #
  # If you want to use the LiveDashboard in production, you should put
  # it behind authentication and allow only admins to access it.
  # If your application does not have an admins-only section yet,
  # you can use Plug.BasicAuth to set up some basic authentication
  # as long as you are also using SSL (which you should anyway).
  if Mix.env() in [:dev, :test] do
    import Phoenix.LiveDashboard.Router

    scope "/" do
      pipe_through :browser
      live_dashboard "/dashboard", metrics: PeggyWeb.Telemetry
    end
  end

  # Enables the Swoosh mailbox preview in development.
  #
  # Note that preview only shows emails that were sent by the same
  # node running the Phoenix server.
  if Mix.env() == :dev do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", PeggyWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/users/register", UserRegistrationController, :new
    post "/users/register", UserRegistrationController, :create
    get "/users/log_in", UserSessionController, :new
    post "/users/log_in", UserSessionController, :create
    get "/users/reset_password", UserResetPasswordController, :new
    post "/users/reset_password", UserResetPasswordController, :create
    get "/users/reset_password/:token", UserResetPasswordController, :edit
    put "/users/reset_password/:token", UserResetPasswordController, :update
  end

  scope "/", PeggyWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/users/settings", UserSettingsController, :edit
    put "/users/settings", UserSettingsController, :update
    get "/users/settings/confirm_email/:token", UserSettingsController, :confirm_email

    get "/clear_set_active_farm/", SetActiveFarmController, :new
    post "/set_active_farm", SetActiveFarmController, :create
    get "/update_active_farm", SetActiveFarmController, :update

    live "/farms", FarmLive.Index, :index
    live "/farms/:id/edit", FarmLive.Form, :edit
    live "/farms/new", FarmLive.Form, :new
  end

  scope "/farms/:farm_id", PeggyWeb do
    pipe_through [:browser, :require_authenticated_user, :require_active_farm]

    live "/navigation", NavigationLive.Index, :index
    live "/invite_users/new", InviteUserLive.New, :new
    live "/users", UserLive.Index, :index
    live "/locations", LocationLive.Index, :index
    live "/sows", SowLive.Index, :index
    live "/boars", BoarLive.Index, :index
  end

  scope "/", PeggyWeb do
    pipe_through [:browser]

    get "/users/force_logout", UserSessionController, :force_logout
    delete "/users/log_out", UserSessionController, :delete
    get "/users/confirm", UserConfirmationController, :new
    post "/users/confirm", UserConfirmationController, :create
    get "/users/confirm/:token", UserConfirmationController, :confirm
  end
end
