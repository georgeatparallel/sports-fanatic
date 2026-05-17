defmodule SportsFanatic.Feeds.CsvParserTest do
  use ExUnit.Case, async: true

  alias SportsFanatic.Feeds.CsvParser

  @tag :unit

  describe "parse/1 with Fantrax format" do
    test "parses standard Fantrax CSV with section headers" do
      csv = """
      "","Hitting"
      "ID","Pos","Player","Team","Eligible","Status","Age"
      "*05lo5*","C","Freddy Fermin","KC/SD","C","Act","31"
      "*2m7jk*","1B","Pete Alonso","NYM","1B","Act","31"
      "","Pitching"
      "ID","Pos","Player","Team","Eligible","Status","Age"
      "*abc12*","SP","Corbin Burnes","ARI","SP","Act","31"
      """

      result = CsvParser.parse(csv)

      assert length(result) == 3
      assert %{player_name: "Freddy Fermin", team_abbreviation: "KC"} in result
      assert %{player_name: "Pete Alonso", team_abbreviation: "NYM"} in result
      assert %{player_name: "Corbin Burnes", team_abbreviation: "ARI"} in result
    end

    test "handles multi-team values by taking first team" do
      csv = """
      "ID","Pos","Player","Team"
      "1","C","Freddy Fermin","KC/SD"
      """

      result = CsvParser.parse(csv)
      assert [%{team_abbreviation: "KC"}] = result
    end
  end

  describe "parse/1 with Yahoo format" do
    test "parses Yahoo roster CSV" do
      csv = """
      Name,Team,Pos
      Aaron Judge,NYY,OF
      Shohei Ohtani,LAD,DH/SP
      Mookie Betts,LAD,OF
      """

      result = CsvParser.parse(csv)

      assert length(result) == 3
      assert %{player_name: "Aaron Judge", team_abbreviation: "NYY"} in result
      assert %{player_name: "Shohei Ohtani", team_abbreviation: "LAD"} in result
    end
  end

  describe "parse/1 with ESPN format" do
    test "parses ESPN-style CSV with Player Name header" do
      csv = """
      Player Name,Tm,Pos,Status
      Juan Soto,NYM,OF,Active
      Fernando Tatis Jr.,SD,OF,Active
      """

      result = CsvParser.parse(csv)

      assert length(result) == 2
      assert %{player_name: "Juan Soto", team_abbreviation: "NYM"} in result
      assert %{player_name: "Fernando Tatis Jr.", team_abbreviation: "SD"} in result
    end
  end

  describe "parse/1 with CBS format" do
    test "parses CBS-style CSV" do
      csv = """
      Full Name,Club,Position
      Mike Trout,LAA,OF
      Ronald Acuna Jr.,ATL,OF
      """

      result = CsvParser.parse(csv)

      assert length(result) == 2
      assert %{player_name: "Mike Trout", team_abbreviation: "LAA"} in result
    end
  end

  describe "parse/1 edge cases" do
    test "returns empty list for empty input" do
      assert CsvParser.parse("") == []
    end

    test "returns empty list for blank lines only" do
      assert CsvParser.parse("\n\n\n") == []
    end

    test "deduplicates players by name" do
      csv = """
      Player,Team
      Aaron Judge,NYY
      Aaron Judge,NYY
      """

      result = CsvParser.parse(csv)
      assert length(result) == 1
    end

    test "skips blank rows" do
      csv = """
      Player,Team
      Aaron Judge,NYY

      Shohei Ohtani,LAD
      """

      result = CsvParser.parse(csv)
      assert length(result) == 2
    end

    test "handles quoted fields with commas" do
      csv = """
      Player,Team,Notes
      "Judge, Aaron",NYY,"Big slugger"
      """

      result = CsvParser.parse(csv)
      assert [%{player_name: "Judge, Aaron"}] = result
    end

    test "handles CSV without team column" do
      csv = """
      Player,Pos,Age
      Aaron Judge,OF,33
      Shohei Ohtani,DH,31
      """

      result = CsvParser.parse(csv)
      assert length(result) == 2
      assert %{player_name: "Aaron Judge", team_abbreviation: nil} in result
    end
  end

  describe "parse_csv_line/1" do
    test "splits unquoted fields" do
      assert CsvParser.parse_csv_line("a,b,c") == ["a", "b", "c"]
    end

    test "handles quoted fields" do
      assert CsvParser.parse_csv_line(~s("hello","world")) == ["hello", "world"]
    end

    test "handles escaped quotes in quoted fields" do
      assert CsvParser.parse_csv_line(~s("say ""hello""",b)) == [~s(say "hello"), "b"]
    end

    test "handles empty fields" do
      assert CsvParser.parse_csv_line("a,,c") == ["a", "", "c"]
    end
  end
end
