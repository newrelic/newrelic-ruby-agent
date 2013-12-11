# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class Marshalling < Performance::TestCase
  def setup
    @payload = build_analytics_events_payload
    @tt_payload = build_transaction_trace_payload
  end

  skip_test :test_basic_marshalling_json, :platforms => :mri_18

  def test_basic_marshalling_json(timer)
    marshaller = NewRelic::Agent::NewRelicService::JsonMarshaller.new
    timer.measure do
      (iterations / 100).times do
        marshaller.dump(@payload)
        marshaller.dump(@tt_payload)
      end
    end
  end

  def test_basic_marshalling_pruby(timer)
    marshaller = NewRelic::Agent::NewRelicService::PrubyMarshaller.new
    timer.measure do
      (iterations / 100).times do
        marshaller.dump(@payload)
        marshaller.dump(@tt_payload)
      end
    end
  end

  # Build an object graph that approximates a transaction trace in structure
  def build_transaction_trace_payload(depth=6)
    root = []
    fanout = depth
    fanout.times do |i|
      node = [
        i * rand(10),
        i * rand(10),
        "This/Is/The/Name/Of/A/Transaction/Trace/Node/Depth/#{depth}/#{i}",
        {
          "sql" => "SELECT #{(0..100).to_a.join(",")}"
        },
        []
      ]
      node[-1] = build_transaction_trace_payload(depth-1) if depth > 0
      root << node
    end
    root
  end

  # Build an object graph that approximates a large analytics_event_data payload
  def build_analytics_events_payload
    events = []
    1000.times do
      event = {
        :timestamp        => Time.now.to_f,
        :name             => "Controller/foo/bar",
        :type             => "Transaction",
        :duration         => rand,
        :webDuration      => rand,
        :databaseDuration => rand,
        :gcCumulative     => rand,
        :color            => 'blue-green',
        :shape            => 'squarish',
        :texture          => 'sort of lumpy like a bag of frozen peas'
      }
      events << [event]
    end
    [rand(1000000), events]
  end
end
