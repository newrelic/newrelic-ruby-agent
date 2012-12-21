require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))

class NewRelic::Agent::CrossProcessMonitoringTest < Test::Unit::TestCase
  def test_finds_id_from_headers
    %w{X-NewRelic-ID HTTP_X_NEWRELIC_ID X_NEWRELIC_ID}.each do |key|
      request = stub(:env => { key => "asdf" })

      assert_equal(
        "asdf", \
        NewRelic::Agent::CrossProcessMonitoring.id_from_request(request),
        "Failed to find header on key #{key}")
    end
  end

  def test_doesnt_find_id_in_headers
    request = stub(:env => {})
    assert_nil NewRelic::Agent::CrossProcessMonitoring.id_from_request(request)
  end
end
