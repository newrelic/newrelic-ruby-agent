# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require "typhoeus"
require "newrelic_rpm"
require "http_client_test_cases"

if NewRelic::Agent::Instrumentation::Typhoeus.is_supported_version?

  class TyphoeusTest < Minitest::Test
    include HttpClientTestCases

    USE_SSL_VERIFYPEER_VERSION  = Gem::Version.new("0.5.0")

    # Starting in version 0.6.4, Typhoeus supports passing URI instances instead
    # of String URLs. Make sure we don't break that.
    SUPPORTS_URI_OBJECT_VERSION = Gem::Version.new("0.6.4")

    CURRENT_TYPHOEUS_VERSION = Gem::Version.new(Typhoeus::VERSION)

    def ssl_option
      if CURRENT_TYPHOEUS_VERSION >= USE_SSL_VERIFYPEER_VERSION
        { :ssl_verifypeer => false }
      else
        { :disable_ssl_peer_verification => true }
      end
    end

    def client_name
      "Typhoeus"
    end

    def timeout_error_class
      Typhoeus::Errors::TyphoeusError
    end

    def simulate_error_response
      get_response "http://localhost:666/evil"
    end

    # We use the Typhoeus::Request rather than right on Typhoeus to support
    # prior to convenience methods being added on the top-level module (0.5.x)
    def get_response(url=nil, headers=nil)
      options = {:headers => headers}.merge(ssl_option)
      Typhoeus::Request.get(url || default_url, options)
    end

    def get_wrapped_response url
      NewRelic::Agent::HTTPClients::TyphoeusHTTPResponse.new get_response url
    end
    
    def head_response
      Typhoeus::Request.head(default_url, ssl_option)
    end

    def post_response
      Typhoeus::Request.post(default_url, ssl_option.merge(:body => ""))
    end

    def put_response
      Typhoeus::Request.put(default_url, ssl_option.merge(:body => ""))
    end

    def delete_response
      Typhoeus::Request.delete(default_url, ssl_option)
    end

    def request_instance
      NewRelic::Agent::HTTPClients::TyphoeusHTTPRequest.new(Typhoeus::Request.new("http://newrelic.com"))
    end

    def response_instance(headers = {})
      headers = headers.map do |k,v|
        "#{k}: #{v}"
      end.join("\r\n")

      NewRelic::Agent::HTTPClients::TyphoeusHTTPResponse.new(Typhoeus::Response.new(:response_headers => headers))
    end

    # NOTE: this definition replaces the one defined in HttpClientTestCases!
    def test_noticed_error_at_segment_and_txn_on_error
      txn = nil
      begin
        in_transaction do |ext_txn|
          txn = ext_txn
          simulate_error_response
        end
      rescue StandardError => e
        # NOP -- allowing span and transaction to notice error
      end
      assert_segment_noticed_error txn, /GET$/, timeout_error_class.name, /timeout|couldn't connect/i

      # Typhoeus doesn't raise errors, so transactions never see it, 
      # which diverges from behavior of other HTTP client libraries
      refute_transaction_noticed_error txn, timeout_error_class.name
    end

    def test_maintains_on_complete_callback_ordering
      invocations = []

      req = Typhoeus::Request.new(default_url, ssl_option)
      req.on_complete { |rsp| invocations << :first }
      req.on_complete { |rsp| invocations << :second }
      req.run

      assert_equal([:first, :second], invocations)
    end

    def test_tracing_succeeds_if_user_set_on_complete_callback_raises
      caught_exception = nil
      in_transaction("test") do
        req = Typhoeus::Request.new(default_url, ssl_option)
        req.on_complete { |rsp| raise 'noodle' }

        begin
          req.run
        rescue => e
          if e.message == 'noodle'
            caught_exception = e
          else
            raise
          end
        end

        refute_nil(caught_exception)
        assert_equal('noodle', caught_exception.message)
      end

      last_node = find_last_transaction_node
      assert_equal "External/localhost/Typhoeus/GET", last_node.metric_name
    end

    def test_request_succeeds_even_if_tracing_doesnt
      in_transaction("test") do
        ::NewRelic::Agent::CrossAppTracing.stubs(:cross_app_enabled?).raises("Booom")
        res = get_response

        assert_match %r/<head>/i, body(res)
        assert_metrics_not_recorded(["External/all"])
      end
    end

    def test_hydra
      in_transaction("test") do
        hydra = Typhoeus::Hydra.new
        5.times { hydra.queue(Typhoeus::Request.new(default_url, ssl_option)) }
        hydra.run
      end

      trace = last_transaction_trace

      hydra = find_node_with_name trace, "External/Multiple/Typhoeus::Hydra/run"

      assert_equal 5, hydra.children.size

      hydra.children.each do |child|
        assert_equal "External/localhost/Typhoeus/GET", child.metric_name
      end

      trace.each_node do |node|
        next if node.metric_name == "ROOT"
        assert node.params.key?(:exclusive_duration_millis), "Expected all nodes (except ROOT) to have :exclusive_duration_millis"
      end

      assert hydra.params[:exclusive_duration_millis] > 0, "Expected a positive exclusive duration"
    end

    def test_noticed_error_at_segment_and_txn_on_error_for_hydra
      txn = nil
      begin
        in_transaction do |ext_txn|
          txn = ext_txn
          hydra = Typhoeus::Hydra.new
          5.times { hydra.queue(Typhoeus::Request.new("http://localhost:666/evil", ssl_option)) }
          hydra.run
        end
      rescue StandardError => e
        # NOP -- allowing span and transaction to notice error
      end

      assert_segment_noticed_error txn, /GET$/, timeout_error_class.name, /timeout|couldn't connect/i

      get_segments = txn.segments.select{|s| s.name =~ /GET$/}
      assert_equal 5, get_segments.size
      assert get_segments.all?{|s| s.noticed_error}, "Expected every GET to notice an error"

      # Typhoeus doesn't raise errors, so transactions never see it, 
      # which diverges from behavior of other HTTP client libraries
      refute_transaction_noticed_error txn, timeout_error_class.name
    end


    if CURRENT_TYPHOEUS_VERSION >= SUPPORTS_URI_OBJECT_VERSION
      def test_get_with_uri
        res = nil
        in_transaction { res = get_response(default_uri) }
        assert_match %r/<head>/i, body(res)
        assert_externals_recorded_for("localhost", "GET")
      end
    end
  end

else

  class TyphoeusNotInstrumented < Minitest::Test
    def test_works_without_instrumentation
      # Typhoeus.get wasn't supported back before 0.5.x
      Typhoeus::Request.get("http://localhost/not/there")
      assert_metrics_not_recorded(["External/all"])
    end
  end

end
