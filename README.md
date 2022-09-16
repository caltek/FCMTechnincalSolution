# FCMSolution

**Techinical Challenge Soltution**

## Installation
This solution depends on [Timex](https://hexdocs.pm/timex), I have used timex for datetime comparison and formatting datetime strins

After cloning this repo please make sure to run 

```elixir
mix deps.get
```
## Tesing The program
After cloning and installing the required dependecies. 
You can test the program in one of 2 ways
- By putting a test file, in the root directory of this repo
```elixir
  iex -S mix 
  >> 
  FCMSolution.parse_file(file_name)
```
- By copy pasting raw data
```elixir
  iex -S mix 
  >> 
  FCMSolution.parse_string("--- raw -- data")
```
## Assumptions
- segments won’t overlap 
- IATAs are always three-letter capital words

## Notes
The solution begins by reading the specified file line by line. 
- The programs then categorizes each line in to three event groups (RESERVATION, SEGMENT, BASE) by checking the first characters of the line. RESERVATION and any other unkown event is simply discarded.
- The program then reduces known events to a final map of 
    ```elixir
    %{
      base: "SVQ",
      trips: [
          %{
            from: "BCN",
            to: nil,
            trip_end: ~N[2023-01-10 00:00:00],
            trip_method: "Hotel",
            trip_start: ~N[2023-01-05 00:00:00]
          },
          ....
        ]
    }
    ```
- After forming the trips state map, the program then iterate over each trips to find departure trips and a corresponding return trip from the base IATA
- After finding departure and return trips, the program then fits other trips which are within the time window of the departure and return trips
    ```elixir
      [
        %{
          detail: [
            %{
              from: "SVQ",
              to: "BCN",
              trip_end: ~N[2023-01-05 22:10:00],
              trip_method: "Flight",
              trip_start: ~N[2023-01-05 20:40:00]
            },
            %{
              from: "BCN",
              to: "SVQ",
              trip_end: ~N[2023-01-10 11:50:00],
              trip_method: "Flight",
              trip_start: ~N[2023-01-10 10:30:00]
            },
            %{
              from: "BCN",
              to: nil,
              trip_end: ~N[2023-01-10 00:00:00],
              trip_method: "Hotel",
              trip_start: ~N[2023-01-05 00:00:00]
            }
          ],
          summary: "TRIP TO BCN"
       },
       ....
      ]

    ```
 - Finally we iterate of the trip summary and pretty print the trip summary info

    ```elixir
      TRIP TO BCN

      Flight from SVQ to BCN 2023-01-05 20:40 to 2023-01-05 22:10
      Hotel at BCN on 2023-01-05 to 2023-01-10
      Flight from BCN to SVQ 2023-01-10 10:30 to 2023-01-10 11:50

      TRIP TO MAD

      Train from SVQ to MAD 2023-02-15 09:30 to 2023-02-15 11:00
      Hotel at MAD on 2023-02-15 to 2023-02-17
      Train from MAD to SVQ 2023-02-17 17:00 to 2023-02-17 19:30
    ```



