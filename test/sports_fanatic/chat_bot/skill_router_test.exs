defmodule SportsFanatic.ChatBot.SkillRouterTest do
  use ExUnit.Case, async: true

  alias SportsFanatic.ChatBot.SkillRouter

  @tag :unit

  describe "route/2 with no active skill" do
    test "routes /help to help skill" do
      assert {:skill, :help} = SkillRouter.route("/help", nil)
    end

    test "routes /register to register skill" do
      assert {:skill, :register} = SkillRouter.route("/register", nil)
    end

    test "routes /login to login skill" do
      assert {:skill, :login} = SkillRouter.route("/login", nil)
    end

    test "routes /add-new-feed to add_feed skill" do
      assert {:skill, :add_feed} = SkillRouter.route("/add-new-feed", nil)
    end

    test "routes /list-feeds to list_feeds skill" do
      assert {:skill, :list_feeds} = SkillRouter.route("/list-feeds", nil)
    end

    test "routes /manage-feeds to manage_feeds skill" do
      assert {:skill, :manage_feeds} = SkillRouter.route("/manage-feeds", nil)
    end

    test "routes /upload to upload skill" do
      assert {:skill, :upload} = SkillRouter.route("/upload", nil)
    end

    test "falls through to agent for unrecognized text" do
      assert {:agent, "what is the weather?"} = SkillRouter.route("what is the weather?", nil)
    end
  end

  describe "route/2 natural language intents" do
    test "routes 'help' to help skill" do
      assert {:skill, :help} = SkillRouter.route("help", nil)
    end

    test "routes 'show my feeds' to list_feeds skill" do
      assert {:skill, :list_feeds} = SkillRouter.route("show my feeds", nil)
    end

    test "routes 'create a feed' to add_feed skill" do
      assert {:skill, :add_feed} = SkillRouter.route("create a feed", nil)
    end

    test "routes 'upload csv' to upload skill" do
      assert {:skill, :upload} = SkillRouter.route("upload csv", nil)
    end

    test "routes 'sign up' to register skill" do
      assert {:skill, :register} = SkillRouter.route("sign up", nil)
    end

    test "routes 'log in' to login skill" do
      assert {:skill, :login} = SkillRouter.route("log in", nil)
    end
  end

  describe "route/2 with active skill state" do
    test "continues active skill with input text" do
      state = %{skill: :register, step: :await_email}
      assert {:continue, :register, "user@test.com"} = SkillRouter.route("user@test.com", state)
    end

    test "cancel breaks out of active skill" do
      state = %{skill: :register, step: :await_email}
      assert {:skill, :cancel} = SkillRouter.route("/cancel", state)
    end

    test "nevermind breaks out of active skill" do
      state = %{skill: :add_feed, step: :await_name}
      assert {:skill, :cancel} = SkillRouter.route("nevermind", state)
    end
  end
end
