defmodule SportsFanatic.Accounts do
  @moduledoc """
  The Accounts context: user registration, authentication, and session management.
  """

  import Ecto.Query
  alias SportsFanatic.Accounts.{Session, User}
  alias SportsFanatic.Repo

  @session_validity_days 30

  # --- User Registration ---

  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: String.downcase(email))
  end

  def get_user!(id), do: Repo.get!(User, id)

  def authenticate_user(email, password) when is_binary(email) and is_binary(password) do
    user = get_user_by_email(email)
    authenticate_user_password(user, password)
  end

  defp authenticate_user_password(nil, _password) do
    # Prevent timing attacks
    Bcrypt.no_user_verify()
    {:error, :invalid_credentials}
  end

  defp authenticate_user_password(user, password) do
    if Bcrypt.verify_pass(password, user.password_hash) do
      {:ok, user}
    else
      {:error, :invalid_credentials}
    end
  end

  # --- Session Management ---

  def create_session(user, conn_info \\ %{}) do
    token = 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64()
    expires_at = DateTime.utc_now() |> DateTime.add(@session_validity_days * 24 * 3600, :second)

    %Session{}
    |> Session.changeset(%{
      user_id: user.id,
      token: token,
      ip_address: Map.get(conn_info, :ip_address),
      user_agent: Map.get(conn_info, :user_agent),
      expires_at: expires_at
    })
    |> Repo.insert()
  end

  def get_user_by_session_token(token) when is_binary(token) do
    now = DateTime.utc_now()

    query =
      from s in Session,
        join: u in User,
        on: s.user_id == u.id,
        where: s.token == ^token and s.expires_at > ^now,
        select: u

    Repo.one(query)
  end

  def delete_session(token) when is_binary(token) do
    Session
    |> where([s], s.token == ^token)
    |> Repo.delete_all()
  end

  def delete_expired_sessions do
    now = DateTime.utc_now()

    Session
    |> where([s], s.expires_at < ^now)
    |> Repo.delete_all()
  end

  # --- Subscription helpers ---

  def update_user_subscription(user, attrs) do
    user
    |> User.subscription_changeset(attrs)
    |> Repo.update()
  end

  def has_active_subscription?(user) do
    user.subscription_tier in ["trial", "monthly", "yearly"] &&
      not is_nil(user.subscription_expires_at) &&
      DateTime.compare(user.subscription_expires_at, DateTime.utc_now()) == :gt
  end
end
