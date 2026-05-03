defmodule SportsFanatic.Repo.Migrations.AddInjuryAreaGradeToNewsItems do
  use Ecto.Migration

  def change do
    alter table(:news_items, prefix: "content") do
      add :injury_area, :string
      add :injury_grade, :string
    end
  end
end
