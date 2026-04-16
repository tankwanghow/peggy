defmodule Peggy.Repo.Migrations.ChangeMovedAtToDate do
  use Ecto.Migration

  def change do
    alter table(:movements) do
      modify :moved_at, :date, from: :utc_datetime, null: false
    end
  end
end
