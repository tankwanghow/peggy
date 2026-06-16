defmodule Peggy.Repo.Migrations.DropTasksTable do
  use Ecto.Migration

  def up do
    execute "DROP TABLE IF EXISTS tasks"
  end

  def down, do: :ok
end
