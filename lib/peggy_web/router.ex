defmodule PeggyWeb.Router do
  use PeggyWeb, :router

  import PeggyWeb.UserAuth
  import PeggyWeb.ActiveFarm

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PeggyWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
    plug :set_active_farm
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
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [{PeggyWeb.UserAuth, :redirect_if_user_is_authenticated}] do
      live "/users/register", UserRegistrationLive, :new
      live "/users/log_in", UserLoginLive, :new
      live "/users/reset_password", UserForgotPasswordLive, :new
      live "/users/reset_password/:token", UserResetPasswordLive, :edit
    end

    post "/users/log_in", UserSessionController, :create
  end

  scope "/", PeggyWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{PeggyWeb.UserAuth, :ensure_authenticated}] do
      live "/users/settings", UserSettingsLive, :edit
      live "/users/settings/confirm_email/:token", UserSettingsLive, :confirm_email
      live("/farms", FarmLiveIndex)
      live("/farms/new", FarmLive.Form, :new)
      live("/edit_farm/:id", FarmLive.Form, :edit)
    end

    post("/update_active_farm", ActiveFarmController, :create)
    get("/delete_active_farm", ActiveFarmController, :delete)
  end

  scope "/farms/:farm_id", PeggyWeb do
    pipe_through([:browser, :require_authenticated_user])

    live_session :require_authenticated_user_n_active_farm,
      on_mount: [
        {PeggyWeb.UserAuth, :ensure_authenticated},
        {PeggyWeb.ActiveFarm, :assign_active_farm}
      ] do
      live("/main", MainLive)
      live("/users/new", UserLive.New, :new)
      live("/users", UserLive.Index, :index)
      live("/rouge_users", UserLive.RougeUserIndex, :index)
      end
    end

  scope "/", PeggyWeb do
    pipe_through [:browser]

    delete "/users/log_out", UserSessionController, :delete

    live_session :current_user,
      on_mount: [{PeggyWeb.UserAuth, :mount_current_user}] do
      live "/users/confirm/:token", UserConfirmationLive, :edit
      live "/users/confirm", UserConfirmationInstructionsLive, :new
    end
  end
end
