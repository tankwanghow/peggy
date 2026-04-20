defmodule Peggy.Repo.Migrations.EnableFuzzystrmatch do
  use Ecto.Migration

  # Provides levenshtein() for near-duplicate ear-tag detection used by
  # the back-fill cascade (PR 5+). Hard-blocks creating an inferred sow
  # whose tag is suspiciously close to an existing one.

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS fuzzystrmatch")
  end

  def down do
    execute("DROP EXTENSION IF EXISTS fuzzystrmatch")
  end
end
