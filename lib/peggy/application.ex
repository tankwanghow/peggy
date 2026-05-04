defmodule Peggy.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        PeggyWeb.Telemetry,
        Peggy.Repo,
        {DNSCluster, query: Application.get_env(:peggy, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Peggy.PubSub},
        PeggyWeb.Endpoint
      ] ++ scheduler_child()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Peggy.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PeggyWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Hourly task scheduler. Disabled in test (controlled by config) so
  # tests don't fire timers and create stray rows.
  defp scheduler_child do
    if Application.get_env(:peggy, :start_scheduler, true) do
      [Peggy.Scheduler]
    else
      []
    end
  end
end
