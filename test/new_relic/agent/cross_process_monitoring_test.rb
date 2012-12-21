require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))

module NewRelic::Agent
  class CrossProcessMonitoringTest < Test::Unit::TestCase
    def setup
      NewRelic::Agent.instance.stubs(:cross_process_id).returns("qwerty")
      NewRelic::Agent.instance.stubs(:cross_process_encoding_bytes).returns([1,2,3,4])

      @request_with_id = stub(:env => {'X-NewRelic-ID' => "asdf"})
      @empty_request = stub(:env => {})

      @response = {}
    end

    def test_adds_response_header
      CrossProcessMonitoring.insert_response_header(@request_with_id, @response)
      assert_equal false, @response['X-NewRelic-App-Data'].nil?
    end

    def test_doesnt_add_header_if_no_id_in_request
      CrossProcessMonitoring.insert_response_header(@empty_request, @response)
      assert_nil @response['X-NewRelic-App-Data']
    end

    def test_doesnt_add_header_if_no_id_on_agent
      NewRelic::Agent.instance.stubs(:cross_process_id).returns(nil)

      CrossProcessMonitoring.insert_response_header(@request_with_id, @response)
      assert_nil @response['X-NewRelic-App-Data']
    end

    def test_finds_id_from_headers
      %w{X-NewRelic-ID HTTP_X_NEWRELIC_ID X_NEWRELIC_ID}.each do |key|
        request = stub(:env => { key => "asdf" })

        assert_equal(
          "asdf", \
          CrossProcessMonitoring.id_from_request(request),
          "Failed to find header on key #{key}")
      end
    end

    def test_doesnt_find_id_in_headers
      request = stub(:env => {})
      assert_nil CrossProcessMonitoring.id_from_request(request)
    end

  end
end
