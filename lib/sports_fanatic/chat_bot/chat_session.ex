defmodule SportsFanatic.ChatBot.ChatSession do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @schema_prefix "accounts"

  schema "chat_sessions" do
    field :status, :string, default: "active"
    field :last_activity_at, :utc_datetime
    field :inserted_at, :utc_datetime

    belongs_to :user, SportsFanatic.Accounts.User, type: :binary_id
    has_many :messages, SportsFanatic.ChatBot.ChatMessage, foreign_key: :session_id
  end

  @valid_statuses ~w(active expired)

  def changeset(session, attrs) do
    session
    |> cast(attrs, [:user_id, :status, :last_activity_at])
    |> validate_required([:user_id])
    |> validate_inclusion(:status, @valid_statuses)
    |> foreign_key_constraint(:user_id)
  end
end
