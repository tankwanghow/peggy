defmodule Peggy.Repo do
  use Ecto.Repo,
    otp_app: :peggy,
    adapter: Ecto.Adapters.Postgres
end
