defmodule SportsFanaticWeb.AuthControllerTest do
  use SportsFanaticWeb.ConnCase, async: true

  alias SportsFanatic.Accounts

  defp unique_email, do: "auth_test_#{System.unique_integer([:positive])}@example.com"

  describe "GET /register" do
    test "renders registration form", %{conn: conn} do
      conn = get(conn, "/register")
      assert html_response(conn, 200) =~ "Create Account"
    end
  end

  describe "POST /register" do
    test "registers user and redirects on valid params", %{conn: conn} do
      email = unique_email()

      conn =
        post(conn, "/register", %{
          "user" => %{"email" => email, "password" => "validpass123"}
        })

      assert redirected_to(conn) == "/"
      assert get_flash(conn, :info) =~ "Account created"
    end

    test "renders form with errors on invalid email", %{conn: conn} do
      conn =
        post(conn, "/register", %{
          "user" => %{"email" => "bademail", "password" => "validpass123"}
        })

      assert html_response(conn, 200) =~ "Create Account"
    end

    test "renders form with errors on short password", %{conn: conn} do
      conn =
        post(conn, "/register", %{
          "user" => %{"email" => unique_email(), "password" => "short"}
        })

      assert html_response(conn, 200) =~ "Create Account"
    end

    test "renders form with errors on duplicate email", %{conn: conn} do
      email = unique_email()
      {:ok, _user} = Accounts.register_user(%{email: email, password: "password123"})

      conn =
        post(conn, "/register", %{
          "user" => %{"email" => email, "password" => "otherpass123"}
        })

      assert html_response(conn, 200) =~ "Create Account"
    end

    test "sets session token on successful registration", %{conn: conn} do
      conn =
        post(conn, "/register", %{
          "user" => %{"email" => unique_email(), "password" => "validpass123"}
        })

      assert get_session(conn, :session_token) != nil
    end
  end

  describe "GET /login" do
    test "renders login form", %{conn: conn} do
      conn = get(conn, "/login")
      assert html_response(conn, 200) =~ "Sign In"
    end
  end

  describe "POST /login" do
    setup do
      email = unique_email()
      {:ok, user} = Accounts.register_user(%{email: email, password: "testpass123"})
      {:ok, email: email, user: user}
    end

    test "redirects to / on valid credentials", %{conn: conn, email: email} do
      conn =
        post(conn, "/login", %{
          "user" => %{"email" => email, "password" => "testpass123"}
        })

      assert redirected_to(conn) == "/"
      assert get_flash(conn, :info) =~ "Welcome back"
    end

    test "sets session token on valid login", %{conn: conn, email: email} do
      conn =
        post(conn, "/login", %{
          "user" => %{"email" => email, "password" => "testpass123"}
        })

      assert get_session(conn, :session_token) != nil
    end

    test "renders login form on invalid password", %{conn: conn, email: email} do
      conn =
        post(conn, "/login", %{
          "user" => %{"email" => email, "password" => "wrongpassword"}
        })

      assert html_response(conn, 200) =~ "Sign In"
      assert get_flash(conn, :error) =~ "Invalid email or password"
    end

    test "renders login form for non-existent user", %{conn: conn} do
      conn =
        post(conn, "/login", %{
          "user" => %{"email" => "nobody@example.com", "password" => "password"}
        })

      assert html_response(conn, 200) =~ "Sign In"
    end
  end

  describe "DELETE /logout" do
    test "clears session and redirects to /", %{conn: conn} do
      email = unique_email()
      {:ok, user} = Accounts.register_user(%{email: email, password: "testpass123"})
      {:ok, session} = Accounts.create_session(user)

      conn =
        conn
        |> put_session(:session_token, session.token)
        |> delete("/logout")

      assert redirected_to(conn) == "/"
      assert get_flash(conn, :info) =~ "Signed out"
    end

    test "does not error when no session exists", %{conn: conn} do
      conn = delete(conn, "/logout")
      assert redirected_to(conn) == "/"
    end
  end
end
