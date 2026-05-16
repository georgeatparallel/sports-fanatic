defmodule SportsFanatic.Feeds.CsvParser do
  @moduledoc """
  Format-agnostic CSV parser for fantasy baseball roster exports.

  Works with any fantasy platform (Fantrax, Yahoo, ESPN, CBS, etc.) by
  auto-detecting player name and team columns from headers. Falls back
  to heuristics when headers are not recognizable.
  """

  @player_headers [
    "player",
    "name",
    "full name",
    "player name",
    "playername",
    "full_name",
    "player_name"
  ]

  @team_headers [
    "team",
    "team name",
    "tm",
    "club",
    "team_name",
    "teamname",
    "org",
    "organization",
    "proteam"
  ]

  @section_headers ~w(hitting pitching batters pitchers hitters catchers infielders outfielders)

  @doc """
  Parses a CSV binary string and returns a list of maps with
  `:player_name` and `:team_abbreviation` keys.

  ## Examples

      iex> CsvParser.parse("Player,Team\\nAaron Judge,NYY\\n")
      [%{player_name: "Aaron Judge", team_abbreviation: "NYY"}]
  """
  def parse(csv_binary) when is_binary(csv_binary) do
    lines =
      csv_binary
      |> String.split(~r/\r?\n/, trim: true)
      |> Enum.reject(&blank_line?/1)

    case lines do
      [] ->
        []

      _ ->
        {player_col, team_col, data_lines} = detect_columns(lines)
        parse_data_lines(data_lines, player_col, team_col)
    end
  end

  # ── Column Detection ─────────────────────────────────────────

  defp detect_columns(lines) do
    # Try each line as a potential header row
    lines
    |> Enum.with_index()
    |> Enum.find_value(fn {line, idx} ->
      fields = parse_csv_line(line)
      lower_fields = Enum.map(fields, &String.downcase(String.trim(&1)))

      player_col = find_column_index(lower_fields, @player_headers)
      team_col = find_column_index(lower_fields, @team_headers)

      if player_col do
        data_lines = Enum.drop(lines, idx + 1)
        {player_col, team_col, data_lines}
      end
    end)
    |> case do
      nil ->
        # No recognizable header: try first column with multi-word strings
        {guess_player_col(lines), nil, lines}

      result ->
        result
    end
  end

  defp find_column_index(lower_fields, candidate_headers) do
    Enum.find_index(lower_fields, fn field ->
      field in candidate_headers
    end)
  end

  defp guess_player_col(lines) do
    # Sample up to 10 lines to find a column that has multi-word strings
    sample =
      lines
      |> Enum.reject(&section_header_line?/1)
      |> Enum.take(10)

    if sample == [] do
      0
    else
      fields_per_line = Enum.map(sample, &parse_csv_line/1)
      max_cols = fields_per_line |> Enum.map(&length/1) |> Enum.max(fn -> 1 end)

      # Score each column by how many multi-word values it contains
      0..(max_cols - 1)
      |> Enum.max_by(
        fn col_idx ->
          Enum.count(fields_per_line, fn fields ->
            field = Enum.at(fields, col_idx, "")
            String.contains?(field, " ") and String.length(field) > 3
          end)
        end,
        fn -> 0 end
      )
    end
  end

  # ── Data Line Parsing ────────────────────────────────────────

  defp parse_data_lines(lines, player_col, team_col) do
    lines
    |> Enum.reject(&section_header_line?/1)
    |> Enum.reject(&header_row?/1)
    |> Enum.reject(&blank_line?/1)
    |> Enum.map(&parse_row(&1, player_col, team_col))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(fn %{player_name: name} -> String.downcase(name) end)
  end

  defp parse_row(line, player_col, team_col) do
    fields = parse_csv_line(line)
    player_raw = Enum.at(fields, player_col)
    team_raw = if team_col, do: Enum.at(fields, team_col), else: nil

    player_name = clean_player_name(player_raw)

    if player_name && player_name != "" do
      team_abbreviation = clean_team(team_raw)
      %{player_name: player_name, team_abbreviation: team_abbreviation}
    end
  end

  defp clean_player_name(nil), do: nil

  defp clean_player_name(raw) do
    raw
    |> String.trim()
    # Remove position suffixes like " - C" or " (SP)"
    |> String.replace(~r/\s*[-]\s*[A-Z]{1,3}\s*$/, "")
    |> String.replace(~r/\s*\([A-Z]{1,3}\)\s*$/, "")
    # Remove leading special chars or IDs
    |> String.replace(~r/^[\*#]+/, "")
    |> String.trim()
    |> case do
      "" -> nil
      name -> name
    end
  end

  defp clean_team(nil), do: nil

  defp clean_team(raw) do
    raw
    |> String.trim()
    |> String.split("/")
    |> List.first()
    |> case do
      nil -> nil
      t -> String.trim(t)
    end
    |> case do
      "" -> nil
      t -> t
    end
  end

  # ── CSV Line Parser ──────────────────────────────────────────

  @doc false
  def parse_csv_line(line) when is_binary(line) do
    parse_fields(String.to_charlist(line), [], [])
    |> Enum.reverse()
  end

  # End of input
  defp parse_fields([], current_field, fields) do
    [IO.chardata_to_string(Enum.reverse(current_field)) | fields]
  end

  # Start of quoted field
  defp parse_fields([?" | rest], [], fields) do
    parse_quoted_field(rest, [], fields)
  end

  # Field separator
  defp parse_fields([?, | rest], current_field, fields) do
    field_value = IO.chardata_to_string(Enum.reverse(current_field))
    parse_fields(rest, [], [field_value | fields])
  end

  # Regular character
  defp parse_fields([char | rest], current_field, fields) do
    parse_fields(rest, [char | current_field], fields)
  end

  # Escaped quote inside quoted field
  defp parse_quoted_field([?", ?" | rest], current_field, fields) do
    parse_quoted_field(rest, [?" | current_field], fields)
  end

  # End of quoted field
  defp parse_quoted_field([?" | rest], current_field, fields) do
    field_value = IO.chardata_to_string(Enum.reverse(current_field))
    # Skip until next comma or end
    skip_to_comma(rest, [field_value | fields])
  end

  # End of input within quoted field
  defp parse_quoted_field([], current_field, fields) do
    [IO.chardata_to_string(Enum.reverse(current_field)) | fields]
  end

  # Regular character in quoted field
  defp parse_quoted_field([char | rest], current_field, fields) do
    parse_quoted_field(rest, [char | current_field], fields)
  end

  defp skip_to_comma([], fields), do: fields
  defp skip_to_comma([?, | rest], fields), do: parse_fields(rest, [], fields)
  defp skip_to_comma([_ | rest], fields), do: skip_to_comma(rest, fields)

  # ── Helpers ──────────────────────────────────────────────────

  defp blank_line?(line) do
    String.trim(line) == "" or line =~ ~r/^[\s,]*$/
  end

  defp section_header_line?(line) do
    trimmed =
      line
      |> String.trim()
      |> String.trim("\"")
      |> String.trim(",")
      |> String.trim("\"")
      |> String.downcase()

    # A section header is a line like `"","Hitting"` or just `Hitting`
    trimmed in @section_headers or
      (not String.contains?(line, ",") and trimmed != "" and not multi_field_line?(line))
  end

  defp multi_field_line?(line) do
    fields = parse_csv_line(line)
    non_empty = Enum.count(fields, fn f -> String.trim(f) != "" end)
    non_empty >= 3
  end

  defp header_row?(line) do
    lower = String.downcase(line)
    # Detect repeated header rows within the data
    String.starts_with?(lower, "\"id\"") or
      String.starts_with?(lower, "id,") or
      (String.contains?(lower, "player") and String.contains?(lower, "team") and
         String.contains?(lower, "pos"))
  end
end
