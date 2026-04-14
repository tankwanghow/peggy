defmodule Peggy.Repo.Migrations.AddUserLocaleAndTimezone do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :locale, :string, null: false, default: "en"
      add :timezone, :string, null: false, default: "Etc/UTC"
    end
  end
end
