defmodule PeggyWeb.BackupController do
  @moduledoc """
  Owner-only endpoint that streams a gzipped JSON backup of the
  current farm.

  The controller pipeline doesn't run the `FarmScope` `on_mount` hook
  (that's LiveView-only), so we resolve farm + membership here from
  the `:farm_slug` URL param.
  """
  use PeggyWeb, :controller

  alias Peggy.Accounts.Scope
  alias Peggy.Backup
  alias Peggy.Farms
  alias Peggy.Policy

  def download(conn, %{"farm_slug" => slug}) do
    user_scope = conn.assigns.current_scope

    with %Scope{user: user} when not is_nil(user) <- user_scope,
         farm when not is_nil(farm) <- Farms.get_farm_by_slug(slug),
         membership when not is_nil(membership) <- Farms.get_membership(user, farm),
         %DateTime{} <- membership.accepted_at,
         scope = Scope.put_farm(user_scope, farm, membership),
         true <- Policy.can?(scope, :delete_farm) do
      {:ok, gz, filename} = Backup.export(scope)

      conn
      |> put_resp_content_type("application/gzip")
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
      |> send_resp(200, gz)
    else
      false ->
        conn
        |> put_flash(:error, "Only farm owners can download backups.")
        |> redirect(to: ~p"/farms/#{slug}/settings")
        |> halt()

      _ ->
        conn
        |> put_flash(:error, "Farm not found.")
        |> redirect(to: ~p"/farms")
        |> halt()
    end
  end
end
