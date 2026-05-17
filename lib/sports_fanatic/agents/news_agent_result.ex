defmodule SportsFanatic.Agents.NewsAgentResult do
  @moduledoc """
  Schema for news agent execution results.

  Each result records the outcome of running a user's agent setting
  against the news feed for a given date.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @schema_prefix "accounts"

  schema "news_agent_results" do
    field :matched_news_item_ids, {:array, :binary_id}, default: []
    field :exa_results, :map
    field :explanation, :string
    field :run_date, :date

    belongs_to :user, SportsFanatic.Accounts.User
    belongs_to :setting, SportsFanatic.Agents.NewsAgentSetting

    field :created_at, :utc_datetime
  end

  @doc "Changeset for creating a new result."
  def changeset(result, attrs) do
    result
    |> cast(attrs, [
      :user_id,
      :setting_id,
      :matched_news_item_ids,
      :exa_results,
      :explanation,
      :run_date
    ])
    |> validate_required([:user_id, :setting_id, :run_date])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:setting_id)
  end
end
