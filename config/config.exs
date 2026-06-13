# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

workspace_assets_config = Path.expand("../../shared_config/assets.exs", __DIR__)

if File.exists?(workspace_assets_config) do
  import_config workspace_assets_config
else
  config :esbuild, version: "0.28.1"
  config :tailwind, version: "4.3.1"
end

config :peggy, :scopes,
  user: [
    default: true,
    module: Peggy.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: Peggy.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :peggy,
  ecto_repos: [Peggy.Repo],
  generators: [timestamp_type: :utc_datetime]

config :peggy, PeggyWeb.Gettext,
  locales: ~w(en ms zh),
  default_locale: "en"

# Configure the endpoint
config :peggy, PeggyWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: PeggyWeb.ErrorHTML, json: PeggyWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Peggy.PubSub,
  live_view: [signing_salt: "TAHhs6OW"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :peggy, Peggy.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild
config :esbuild,
  peggy: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind
config :tailwind,
  peggy: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Time zone database — needed for `DateTime.now/1` and `shift_zone/2`
# to handle real zones like "Asia/Singapore". Without this the stdlib
# only knows about UTC.
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
