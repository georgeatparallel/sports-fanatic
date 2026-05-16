defmodule SportsFanatic.ChatBot.ChatMessage do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @schema_prefix "accounts"

  schema "chat_messages" do
    field :role, :string
    field :content, :string
    field :metadata, :map, default: %{}
    field :news_item_ids, {:array, :binary_id}, default: []
    field :inserted_at, :utc_datetime

    belongs_to :session, SportsFanatic.ChatBot.ChatSession, type: :binary_id
  end

  @valid_roles ~w(user assistant progress)

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:session_id, :role, :content, :metadata, :news_item_ids])
    |> validate_required([:session_id, :role, :content])
    |> validate_inclusion(:role, @valid_roles)
    |> validate_length(:content, min: 1, max: 10_000)
    |> foreign_key_constraint(:session_id)
  end
end
