defmodule FcmSolution do
  @moduledoc """
  Documentation for `FcmSolution`.
  """

  @doc """
  Parse Raw File
  """
  def parse_file(file_name) do
    File.read(file_name)
    |> case do
      {:ok, file} ->
        file
        |> String.split("\n")
        |> parse_events()
        |> group_segments_to_trips()
        |> print_summary()

      {:error, _error} ->
        raise "INVALID DATA"
    end
  end

  def parse_string(data_string) do
    data_string
    |> String.split("\n")
    |> parse_events()
    |> group_segments_to_trips()
    |> print_summary()
  end

  def parse_events(event_list) do
    event_list
    |> Enum.reduce(%{base: nil, trips: []}, fn event, acc ->
      event
      |> get_event_type()
      |> case do
        {:ok, :base, line} ->
          base = parse_base_event(line)
          %{acc | base: base}

        {:ok, :segment, line} ->
          with event when is_map(event) <- parse_segment(line) do
            %{trips: prev_trips} = acc
            trip = parse_segment(line)
            %{acc | trips: [trip | prev_trips]}
          else
            _other ->
              IO.puts("UNABLE TO PARSE SEGMENT; #{line}")
              acc
          end

        {:ok, :reservation, _line} ->
          acc

        {:ok, :unknown, _line} ->
          acc
      end
    end)
  end

  def sort_events(trips) do
    trips
    |> Enum.sort_by(& &1.start_time, {:desc, NaiveDateTime})
  end

  def get_event_type(line) do
    trimmed = String.trim(line)

    cond do
      String.starts_with?(trimmed, "BASED") -> {:ok, :base, trimmed}
      String.starts_with?(trimmed, "RESERVATION") -> {:ok, :reservation, trimmed}
      String.starts_with?(trimmed, "SEGMENT") -> {:ok, :segment, trimmed}
      true -> {:ok, :unknown, trimmed}
    end
  end

  defp parse_base_event(line) do
    line
    |> String.split(":\s")
    |> List.last()
  end

  defp parse_segment(line) do
    with [trip_start, trip_end] <-
           line |> String.split(":\s") |> List.last() |> String.trim() |> String.split("->"),
         {:ok,
          %{trip_method: trip_method, from: from, trip_start: trip_start, start_date: st_date}} <-
           parse_segment_start(trip_start),
         {:ok, event_end} <- parse_segment_end_time(st_date, trip_end),
         dest <- parse_segment_destination(trip_end) do
      %{
        trip_method: trip_method,
        from: from,
        trip_start: trip_start,
        to: dest,
        trip_end: event_end
      }
    end
  end

  defp parse_segment_start(segment_start) do
    segment_start
    |> String.trim()
    |> String.split("\s")
    |> case do
      [trip_method, from, start_date | time] ->
        with {:ok, trip_start} <-
               Enum.join(List.flatten([start_date, time]), "\s") |> String.trim() |> get_time() do
          {:ok,
           %{trip_method: trip_method, from: from, trip_start: trip_start, start_date: start_date}}
        end

      _other ->
        {:error, :invalid_segment_start}
    end
  end

  def parse_segment_destination(segment_end) do
    trimmed = String.trim(segment_end)

    cond do
      String.match?(trimmed, ~r/^[A-Z]{3}/) ->
        trimmed
        |> String.split("\s")
        |> List.first()

      true ->
        nil
    end
  end

  defp parse_segment_end_time(start_date, segment_end) do
    trimmed = String.trim(segment_end)

    cond do
      String.match?(trimmed, ~r/^[A-Z]{3}/) ->
        trimmed
        |> String.split("\s")
        |> List.last()
        |> then(&"#{start_date} #{&1}")
        |> get_time()

      true ->
        trimmed
        |> get_time()
    end
  end

  defp get_time(datetime_string) do
    datetime_string
    |> String.trim()
    |> Timex.parse("{YYYY}-{0M}-{D}")
    |> case do
      {:ok, _date} = resp ->
        resp

      {:error, _inv_format} ->
        Timex.parse(datetime_string, "{YYYY}-{0M}-{D} {h24}:{m}")
    end
  end

  def print_summary(trip_group) do
    trip_group
    |> Enum.each(fn %{summary: summary, detail: detail} ->
      IO.puts(summary)
      IO.puts("\n")

      detail
      |> Enum.sort_by(& &1[:trip_end], {:asc, NaiveDateTime})
      |> Enum.each(fn %{
                        to: to,
                        trip_start: trip_start,
                        trip_end: trip_end,
                        from: from,
                        trip_method: method
                      } ->
        case to do
          nil ->
            IO.puts(
              ~s(#{method} at #{from} on #{pretty_print_datetime(trip_start)} to #{pretty_print_datetime(trip_end)})
            )

          _else ->
            IO.puts(
              ~s(#{method} from #{from} to #{to} #{pretty_print_datetime(trip_start)} to #{pretty_print_datetime(trip_end)})
            )
        end
      end)

      IO.puts("\n")
    end)
  end

  def group_segments_to_trips(%{base: base, trips: trips}) do
    dep_return_trip_pair(base, trips)
    |> Enum.reduce([], fn [%{trip_start: dp_start, to: dp_to} = dp_trip, rt_trip], acc ->
      case rt_trip do
        nil ->
          md_trips =
            Enum.filter(trips, fn %{trip_end: ev_end, to: to, from: from} ->
              to == nil and from == dp_to and ev_end >= dp_start
            end)

          middle_trips = [dp_trip] ++ md_trips
          [%{summary: "TRIP TO #{dp_to}", detail: middle_trips} | acc]

        %{trip_end: rt_end, to: rt_to} ->
          md_trips =
            Enum.filter(trips, fn %{trip_start: ev_start, trip_end: ev_end, to: to, from: from} ->
              (to == nil and from == dp_to and ev_end >= dp_start) or
                (to != rt_to and ev_start > dp_start and ev_end < rt_end)
            end)

          middle_trips = [dp_trip, rt_trip] ++ md_trips
          [%{summary: "TRIP TO #{dp_to}", detail: middle_trips} | acc]
      end
    end)
  end

  def dep_return_trip_pair(base, trips) do
    base
    |> find_departure_trips(trips)
    |> Enum.sort_by(& &1[:trip_start], {:desc, NaiveDateTime})
    |> Enum.map(fn %{trip_end: departure_end, to: dp_from} = dp_trip ->
      rt_trip = find_return_trip(departure_end, dp_from, base, trips)
      [dp_trip, rt_trip]
    end)
  end

  defp find_departure_trips(base, trips) do
    trips
    |> Enum.filter(fn %{from: from} -> from == base end)
  end

  defp find_return_trip(departure_end, from, base, trips) do
    trips
    |> Enum.filter(fn %{to: to, from: trip_from} -> to == base and from == trip_from end)
    |> Enum.sort_by(
      fn %{trip_start: tp_start} ->
        Timex.diff(tp_start, departure_end)
      end,
      :asc
    )
    |> List.first()
  end

  defp pretty_print_datetime(date) do
    Timex.format!(date, "{YYYY}-{0M}-{0D} {h24}:{m}")
    |> String.trim_trailing("00:00")
    |> String.trim()
  end
end
