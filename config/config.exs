# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
use Mix.Config

config :peggy,
  ecto_repos: [Peggy.Repo]

# Configures the endpoint
config :peggy, PeggyWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "Z2zXQR5BOVec0+KiS2xrLRSuHxpSB/rNhqEu+ifeamvDCfGU0nW4TbTUfBH6UbGZ",
  render_errors: [view: PeggyWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: Peggy.PubSub,
  live_view: [signing_salt: "EMouvNH/"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"

config :peggy, Peggy.Mailer,
  adapter: Bamboo.SMTPAdapter,
  server: "smtp.mail.yahoo.com",
  hostname: "yahoo.domain",
  port: 465,
  username: "tankwanghow@yahoo.com", # or {:system, "SMTP_USERNAME"}
  password: "rmzbjtwtypauxueg", # or {:system, "SMTP_PASSWORD"}
  tls: :if_available, # can be `:always` or `:never`
  allowed_tls_versions: [:"tlsv1", :"tlsv1.1", :"tlsv1.2"], # or {:system, "ALLOWED_TLS_VERSIONS"} w/ comma seprated values (e.g. "tlsv1.1,tlsv1.2")
  tls_log_level: :error,
  ssl: true, # can be `true`
  retries: 1,
  no_mx_lookups: false, # can be `true`
  auth: :if_available # can be `:always`. If your smtp relay requires authentication set it to `:always`.
