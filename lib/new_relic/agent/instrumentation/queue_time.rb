module NewRelic
  module Agent
    module Instrumentation
      module QueueTime
        MAIN_HEADER = 'X_REQUEST_START'
        
        HEADER_REGEX = /([^\s\/,(t=)]+)? ?t=([0-9]+)/
        SERVER_METRIC = 'WebFrontend/WebServer/'
        ALL_METRIC = 'WebFrontend/WebServer/all'

        # main method to extract queue time info from env hash,
        # records individual server metrics and one roll-up for all servers
        def parse_queue_time_from(env)
          start_time = Time.now
          matches = env[MAIN_HEADER].to_s.scan(HEADER_REGEX).map do |name, time|
            [name, convert_from_microseconds(time.to_i)]
          end
          record_individual_server_stats(start_time, matches)
          record_rollup_stat(start_time, matches)
        end
        
        private

        # goes through the list of servers and records each one in
        # reverse order, subtracting the time for each successive
        # server from the earlier ones in the list.
        # an example because it's complicated:
        # start data:
        # [['a', Time.at(1000)], ['b', Time.at(1001)]], start time: Time.at(1002)
        # initial run: Time.at(1002), ['b', Time.at(1001)]
        # next: Time.at(1001), ['a', Time.at(1000)]
        # see tests for more
        def record_individual_server_stats(end_time, matches) # (Time, [[String, Time]]) -> nil
          matches = matches.sort_by {|name, time| time }
          matches.reverse!
          matches.inject(end_time) {|start_time, pair|
            name, time = pair
            record_queue_time_for(name, time, start_time)
            time
          }
        end

        # records the total time for all servers in a rollup metric
        def record_rollup_stat(start_time, matches) # (Time, [String, Time]) -> nil
          # default to the start time if we have no header
          oldest_time = find_oldest_time(matches) || start_time
          record_time_stat(ALL_METRIC, oldest_time, start_time)
        end
        
        # searches for the first server to touch a request
        def find_oldest_time(matches) # [[String, Time]] -> Time
          matches.map do |name, time|
            time
          end.min
        end
        
        # basically just assembles the metric name
        def record_queue_time_for(name, time, start_time) # (Maybe String, Time, Time) -> nil
          record_time_stat(SERVER_METRIC + name, time, start_time) if name
        end

        # Checks that the time is not negative, and does the actual
        # data recording
        def record_time_stat(name, start_time, end_time) # (String, Time, Time) -> nil
          total_time = end_time - start_time
          if total_time < 0
            raise 'should not provide an end time less than start time'
          else
            NewRelic::Agent.get_stats(name).trace_call(total_time)
          end
        end

        # convert a time to the value provided by the header, for convenience
        def convert_to_microseconds(time) # Time -> Int
          raise TypeError.new('Cannot convert a non-time into microseconds') unless time.is_a?(Time) || time.is_a?(Numeric)
          return time if time.is_a?(Numeric)
          (time.to_f * 1000000).to_i
        end
        
        # convert a time from the header value (time in microseconds)
        # into a ruby time object
        def convert_from_microseconds(int) # Int -> Time
          raise TypeError.new('Cannot convert a non-number into a time') unless int.is_a?(Time) || int.is_a?(Numeric)
          return int if int.is_a?(Time)          
          Time.at((int.to_f / 1000000))
        end
      end
    end
  end
end

