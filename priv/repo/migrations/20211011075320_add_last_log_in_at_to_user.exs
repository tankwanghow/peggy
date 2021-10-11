defmodule Peggy.Repo.Migrations.AddLastLogInAtToUser do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :last_log_in_at, :naive_datetime
    end
  end
end
