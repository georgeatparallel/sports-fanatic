defmodule SportsFanatic.X.PostChangesetTest do
  use ExUnit.Case, async: true

  alias SportsFanatic.X.Post

  # Valid minimal attrs for a post changeset
  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        post_type: "top_hits",
        status: "pending",
        scheduled_at: ~U[2026-06-15 17:30:00Z]
      },
      overrides
    )
  end

  defp changeset(attrs), do: Post.changeset(%Post{}, attrs)

  # ---------------------------------------------------------------------------
  # Required fields
  # ---------------------------------------------------------------------------

  describe "required fields" do
    test "valid attrs produce a valid changeset" do
      cs = changeset(valid_attrs())
      assert cs.valid?
    end

    test "missing post_type is invalid" do
      cs = changeset(valid_attrs() |> Map.delete(:post_type))
      refute cs.valid?
      assert {:post_type, _} = List.keyfind(cs.errors, :post_type, 0)
    end

    test "missing status in attrs uses default 'pending' (field has schema default)" do
      # The Post schema defines `field :status, :string, default: "pending"`.
      # When status is absent from attrs, Ecto uses the schema default — so the
      # changeset remains valid. Explicit nil overrides the default and fails.
      cs = changeset(valid_attrs() |> Map.delete(:status))
      # Still valid because schema default "pending" is applied
      assert cs.valid?
    end

    test "nil status (explicit override) is invalid" do
      cs = changeset(valid_attrs(%{status: nil}))
      refute cs.valid?
      assert {:status, _} = List.keyfind(cs.errors, :status, 0)
    end

    test "missing scheduled_at is invalid" do
      cs = changeset(valid_attrs() |> Map.delete(:scheduled_at))
      refute cs.valid?
      assert {:scheduled_at, _} = List.keyfind(cs.errors, :scheduled_at, 0)
    end
  end

  # ---------------------------------------------------------------------------
  # post_type enum validation
  # ---------------------------------------------------------------------------

  describe "post_type enum" do
    for pt <- ~w(top_hits injury team_magazine scorecard reply) do
      test "accepts valid post_type #{pt}" do
        cs = changeset(valid_attrs(%{post_type: unquote(pt)}))
        assert cs.valid?, "Expected #{unquote(pt)} to be valid"
      end
    end

    test "rejects unknown post_type" do
      cs = changeset(valid_attrs(%{post_type: "shitpost"}))
      refute cs.valid?
      assert {:post_type, _} = List.keyfind(cs.errors, :post_type, 0)
    end

    test "rejects nil post_type" do
      cs = changeset(valid_attrs(%{post_type: nil}))
      refute cs.valid?
    end
  end

  # ---------------------------------------------------------------------------
  # status enum validation
  # ---------------------------------------------------------------------------

  describe "status enum" do
    for st <- ~w(pending approved posted failed rejected cancelled) do
      test "accepts valid status #{st}" do
        cs = changeset(valid_attrs(%{status: unquote(st)}))
        assert cs.valid?, "Expected status #{unquote(st)} to be valid"
      end
    end

    test "rejects unknown status" do
      cs = changeset(valid_attrs(%{status: "limbo"}))
      refute cs.valid?
      assert {:status, _} = List.keyfind(cs.errors, :status, 0)
    end
  end

  # ---------------------------------------------------------------------------
  # main_body length limit
  # Note: The changeset enforces max: 1000, but X v2 enforces 280. The
  # sanitize_and_validate/1 function enforces the 280-char limit at post-time.
  # The test documents the current changeset-level limit.
  # ---------------------------------------------------------------------------

  describe "main_body length" do
    test "accepts main_body up to 1000 chars" do
      body = String.duplicate("a", 1000)
      cs = changeset(valid_attrs(%{main_body: body}))
      assert cs.valid?
    end

    test "rejects main_body over 1000 chars" do
      body = String.duplicate("a", 1001)
      cs = changeset(valid_attrs(%{main_body: body}))
      refute cs.valid?
      assert {:main_body, _} = List.keyfind(cs.errors, :main_body, 0)
    end

    test "accepts nil main_body (optional field)" do
      cs = changeset(valid_attrs(%{main_body: nil}))
      assert cs.valid?
    end

    test "accepts empty main_body" do
      cs = changeset(valid_attrs(%{main_body: ""}))
      assert cs.valid?
    end
  end

  # ---------------------------------------------------------------------------
  # URL detection in main_body — the X.sanitize_and_validate/1 function rejects
  # URLs in main_body. The changeset does NOT enforce this; the 280-char enforcement
  # is also at sanitize_and_validate. We document the boundary clearly.
  # ---------------------------------------------------------------------------

  describe "URL detection boundary (changeset vs. sanitize_and_validate)" do
    test "changeset does NOT reject URLs in main_body (enforced at post-time)" do
      # This is intentional design: the changeset stores drafts; URL rejection
      # happens in X.sanitize_and_validate/1 at actual post time.
      cs = changeset(valid_attrs(%{main_body: "Check out https://example.com for stats"}))

      assert cs.valid?,
             "Changeset should not reject URLs — that is sanitize_and_validate's job"
    end

    test "reply_body allows URLs (self-reply path uses :allow_url)" do
      cs = changeset(valid_attrs(%{reply_body: "https://sportsfanatic.com/mlb/players"}))
      assert cs.valid?
    end
  end

  # ---------------------------------------------------------------------------
  # reply_body length limit
  # ---------------------------------------------------------------------------

  describe "reply_body length" do
    test "accepts reply_body up to 1000 chars" do
      body = String.duplicate("x", 1000)
      cs = changeset(valid_attrs(%{reply_body: body}))
      assert cs.valid?
    end

    test "rejects reply_body over 1000 chars" do
      body = String.duplicate("x", 1001)
      cs = changeset(valid_attrs(%{reply_body: body}))
      refute cs.valid?
      assert {:reply_body, _} = List.keyfind(cs.errors, :reply_body, 0)
    end
  end

  # ---------------------------------------------------------------------------
  # link_url length limit
  # ---------------------------------------------------------------------------

  describe "link_url length" do
    test "rejects link_url over 500 chars" do
      url = "https://example.com/" <> String.duplicate("a", 490)
      cs = changeset(valid_attrs(%{link_url: url}))
      refute cs.valid?
      assert {:link_url, _} = List.keyfind(cs.errors, :link_url, 0)
    end
  end

  # ---------------------------------------------------------------------------
  # post_types/0 and statuses/0 class functions
  # ---------------------------------------------------------------------------

  describe "Post.post_types/0 and statuses/0" do
    test "post_types/0 returns a list of strings" do
      types = Post.post_types()
      assert is_list(types)
      assert Enum.all?(types, &is_binary/1)
    end

    test "statuses/0 returns a list of strings" do
      statuses = Post.statuses()
      assert is_list(statuses)
      assert Enum.all?(statuses, &is_binary/1)
    end

    test "post_types/0 includes the 5 expected types" do
      types = MapSet.new(Post.post_types())
      assert MapSet.subset?(MapSet.new(~w(top_hits injury team_magazine scorecard reply)), types)
    end

    test "statuses/0 includes the 6 expected statuses" do
      statuses = MapSet.new(Post.statuses())

      assert MapSet.subset?(
               MapSet.new(~w(pending approved posted failed rejected cancelled)),
               statuses
             )
    end
  end
end
