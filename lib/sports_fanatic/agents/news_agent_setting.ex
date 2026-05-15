defmodule SportsFanatic.Agents.NewsAgentSetting do
  @moduledoc """
  Schema for user-defined news agent settings.

  Each setting represents a natural language instruction that gets parsed
  by an LLM into structured criteria for matching news articles.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @schema_prefix "accounts"

  @valid_statuses ~w(pending active running completed failed expired)

  schema "news_agent_settings" do
    field :raw_prompt, :string
    field :parsed_criteria, :map
    field :status, :string, default: "pending"
    field :last_run_at, :utc_datetime
    field :last_result, :map
    field :error_message, :string

    belongs_to :user, SportsFanatic.Accounts.User

    has_many :results, SportsFanatic.Agents.NewsAgentResult, foreign_key: :setting_id

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for creating a new setting."
  def create_changeset(setting, attrs) do
    setting
    |> cast(attrs, [:user_id, :raw_prompt])
    |> validate_required([:user_id, :raw_prompt])
    |> validate_length(:raw_prompt, max: 500, message: "must be 500 characters or fewer")
    |> put_change(:status, "pending")
    |> foreign_key_constraint(:user_id)
  end

  @doc "Changeset for updating a setting after LLM parsing or execution."
  def update_changeset(setting, attrs) do
    setting
    |> cast(attrs, [:parsed_criteria, :status, :last_run_at, :last_result, :error_message])
    |> validate_required([:status])
    |> validate_inclusion(:status, @valid_statuses)
  end
end
