defmodule SportsFanatic.JoshuaAuthTest do
  use ExUnit.Case, async: true

  alias SportsFanatic.JoshuaAuth

  @test_username "sf_admin_testuser12345678"
  @test_password "testpassword1234567890123456789012345678901234567890123456789012"

  setup do
    # Store original values
    orig_user = Application.get_env(:sports_fanatic, :joshua_username)
    orig_pass = Application.get_env(:sports_fanatic, :joshua_password)

    # Set test credentials
    Application.put_env(:sports_fanatic, :joshua_username, @test_username)
    Application.put_env(:sports_fanatic, :joshua_password, @test_password)

    on_exit(fn ->
      if orig_user,
        do: Application.put_env(:sports_fanatic, :joshua_username, orig_user),
        else: Application.delete_env(:sports_fanatic, :joshua_username)

      if orig_pass,
        do: Application.put_env(:sports_fanatic, :joshua_password, orig_pass),
        else: Application.delete_env(:sports_fanatic, :joshua_password)
    end)

    :ok
  end

  describe "verify_credentials/2" do
    test "returns :ok for valid credentials" do
      assert :ok = JoshuaAuth.verify_credentials(@test_username, @test_password)
    end

    test "returns error for wrong username" do
      assert {:error, :invalid_credentials} =
               JoshuaAuth.verify_credentials("wrong", @test_password)
    end

    test "returns error for wrong password" do
      assert {:error, :invalid_credentials} =
               JoshuaAuth.verify_credentials(@test_username, "wrong")
    end

    test "returns error for both wrong" do
      assert {:error, :invalid_credentials} = JoshuaAuth.verify_credentials("wrong", "wrong")
    end

    test "returns error for empty strings" do
      assert {:error, :invalid_credentials} = JoshuaAuth.verify_credentials("", "")
    end

    test "returns error for nil values" do
      assert {:error, :invalid_credentials} = JoshuaAuth.verify_credentials(nil, nil)
    end

    test "returns error when credentials not configured" do
      Application.put_env(:sports_fanatic, :joshua_username, nil)
      Application.put_env(:sports_fanatic, :joshua_password, nil)

      assert {:error, :not_configured} = JoshuaAuth.verify_credentials("user", "pass")
    end

    test "returns error when username is empty string in config" do
      Application.put_env(:sports_fanatic, :joshua_username, "")
      Application.put_env(:sports_fanatic, :joshua_password, @test_password)

      assert {:error, :not_configured} = JoshuaAuth.verify_credentials("user", "pass")
    end
  end

  describe "session_expired?/1" do
    test "returns true for nil" do
      assert JoshuaAuth.session_expired?(nil) == true
    end

    test "returns false for recent timestamp" do
      recent = System.system_time(:second) - 100
      assert JoshuaAuth.session_expired?(recent) == false
    end

    test "returns true for timestamp older than 24 hours" do
      old = System.system_time(:second) - 86_401
      assert JoshuaAuth.session_expired?(old) == true
    end

    test "returns false for exactly 24 hours (boundary)" do
      boundary = System.system_time(:second) - 86_400
      assert JoshuaAuth.session_expired?(boundary) == false
    end

    test "returns true for non-integer values" do
      assert JoshuaAuth.session_expired?("not_a_number") == true
    end
  end

  describe "session_ttl_seconds/0" do
    test "returns 86400 (24 hours)" do
      assert JoshuaAuth.session_ttl_seconds() == 86_400
    end
  end
end
