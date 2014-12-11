# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class QueueTimePerfTests < Performance::TestCase
  def setup
    @headers = [
      { 'HTTP_X_REQUEST_START' => "t=1409849996.2152882" },
      { 'HTTP_X_REQUEST_START' => "t=1409850011020.236"  },
      { 'HTTP_X_REQUEST_START' => "t=1409850011020236.0" },
    ]
  end

  def test_queue_time_parsing
    measure do
      @headers.each do |h|
        NewRelic::Agent::Instrumentation::QueueTime.parse_frontend_timestamp(h)
      end
    end
  end
end
