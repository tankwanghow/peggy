defmodule Peggy.Repo.Migrations.AddMembershipIsDefault do
  use Ecto.Migration

  def change do
    alter table(:memberships) do
      add :is_default, :boolean, null: false, default: false
    end

    create unique_index(:memberships, [:user_id],
             where: "is_default",
             name: :memberships_one_default_per_user
           )
  end
end
