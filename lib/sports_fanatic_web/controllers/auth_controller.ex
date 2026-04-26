defmodule SportsFanaticWeb.AuthController do
  use SportsFanaticWeb, :controller

  alias SportsFanatic.Accounts

  def register_form(conn, _params) do
    conn
    |> assign(:page_title, "Create Account | Sports Fan Agent")
    |> render(:register)
  end

  def register(conn, %{"user" => user_params}) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        {:ok, session} = Accounts.create_session(user, conn_info(conn))

        return_to = get_session(conn, :return_to) || "/"

        conn
        |> put_session(:session_token, session.token)
        |> delete_session(:return_to)
        |> put_flash(:info, "Account created successfully!")
        |> redirect(to: return_to)

      {:error, changeset} ->
        conn
        |> assign(:page_title, "Create Account | Sports Fan Agent")
        |> assign(:changeset, changeset)
        |> put_flash(:error, "Could not create account. Please check the errors below.")
        |> render(:register)
    end
  end

  def login_form(conn, params) do
    conn =
      case params["return_to"] do
        "/" <> _rest = path ->
          if String.starts_with?(path, "//") do
            conn
          else
            put_session(conn, :return_to, path)
          end

        _ ->
          conn
      end

    conn
    |> assign(:page_title, "Sign In | Sports Fan Agent")
    |> render(:login)
  end

  def login(conn, %{"user" => %{"email" => email, "password" => password}}) do
    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        {:ok, session} = Accounts.create_session(user, conn_info(conn))

        return_to = get_session(conn, :return_to) || "/"

        conn
        |> put_session(:session_token, session.token)
        |> delete_session(:return_to)
        |> put_flash(:info, "Welcome back!")
        |> redirect(to: return_to)

      {:error, _reason} ->
        conn
        |> assign(:page_title, "Sign In | Sports Fan Agent")
        |> put_flash(:error, "Invalid email or password.")
        |> render(:login)
    end
  end

  def logout(conn, _params) do
    if token = get_session(conn, :session_token) do
      Accounts.delete_session(token)
    end

    conn
    |> configure_session(drop: true)
    |> put_flash(:info, "Signed out successfully.")
    |> redirect(to: "/")
  end

  defp conn_info(conn) do
    %{
      ip_address: conn.remote_ip |> :inet.ntoa() |> to_string(),
      user_agent: conn |> get_req_header("user-agent") |> List.first()
    }
  end
end
