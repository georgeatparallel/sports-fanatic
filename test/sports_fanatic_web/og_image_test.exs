defmodule SportsFanaticWeb.OgImageTest do
  use ExUnit.Case, async: true

  @og_image_path Path.join([:code.priv_dir(:sports_fanatic), "static", "images", "og-default.png"])
  @max_bytes 204_800

  describe "priv/static/images/og-default.png" do
    test "file exists" do
      assert File.exists?(@og_image_path),
             "#{@og_image_path} does not exist — coding agent must commit the PNG"
    end

    test "file is non-empty" do
      assert File.stat!(@og_image_path).size > 0
    end

    test "file size is within the 200 KB budget" do
      size = File.stat!(@og_image_path).size

      assert size <= @max_bytes,
             "og-default.png is #{size} bytes (#{Float.round(size / 1024, 1)} KB), " <>
               "budget is #{@max_bytes} bytes (200 KB)"
    end

    test "file is a valid PNG (magic bytes are correct)" do
      <<137, 80, 78, 71, 13, 10, 26, 10, _rest::binary>> = File.read!(@og_image_path)
    end

    test "image is 1200 pixels wide" do
      <<137, 80, 78, 71, 13, 10, 26, 10, _length::32, "IHDR", width::32, _height::32, _::binary>> =
        File.read!(@og_image_path)

      assert width == 1200, "expected PNG width 1200, got #{width}"
    end

    test "image is 630 pixels tall" do
      <<137, 80, 78, 71, 13, 10, 26, 10, _length::32, "IHDR", _width::32, height::32, _::binary>> =
        File.read!(@og_image_path)

      assert height == 630, "expected PNG height 630, got #{height}"
    end
  end
end
