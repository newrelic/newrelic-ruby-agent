# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'grape'
require 'newrelic_rpm'
require './grape_test_api'

class GrapeTest < Minitest::Test
  include Rack::Test::Methods
  include MultiverseHelpers

  TestRoute = Struct.new(:path, :request_method, :version)

  setup_and_teardown_agent

  unless ::Grape::VERSION == '0.1.5'
    def app
      Rack::Builder.app { run(GrapeTestApi.new) }
    end

    def test_framework_assignment
      assert_equal(:grape, NewRelic::Agent.config[:framework])
    end

    def test_nonexistent_route
      get('/not_grape_ape')

      assert_no_metrics_match(/grape_ape/)
    end

    def test_route_raises_an_error
      assert_raises(GrapeTestApiError) do
        get('/self_destruct')
      end

      expected_txn_name = 'Controller/Grape/GrapeTestApi/self_destruct (GET)'

      assert_metrics_recorded(expected_txn_name)
      assert_metrics_recorded(["Errors/#{expected_txn_name}"])
    end

    def test_getting_a_list_of_grape_apes
      get('/grape_ape')

      assert_metrics_recorded('Controller/Grape/GrapeTestApi/grape_ape (GET)')
    end

    def test_showing_a_grape_ape
      get('/grape_ape/1')

      assert_metrics_recorded('Controller/Grape/GrapeTestApi/grape_ape/:id (GET)')
    end

    def test_creating_a_grape_ape
      post('/grape_ape', {})

      assert_metrics_recorded('Controller/Grape/GrapeTestApi/grape_ape (POST)')
    end

    def test_updating_a_grape_ape
      put('/grape_ape/1', {})

      assert_metrics_recorded('Controller/Grape/GrapeTestApi/grape_ape/:id (PUT)')
    end

    def test_deleting_a_grape_ape
      delete('/grape_ape/1')

      assert_metrics_recorded('Controller/Grape/GrapeTestApi/grape_ape/:id (DELETE)')
    end

    def test_transaction_renaming
      get('/grape_ape/renamed')
      # The second node here is 'Rack' because of an idiosyncrasy of
      # the set_transaction_name API: when you call set_transaction_name and
      # don't provide an explicit category, you lock in the category prefix
      # that was in use at the time you made the call.
      #
      # We may change this behavior in the future, once we have a better
      # internal representation of the name and category of a transaction as
      # truly separate entities.
      #
      assert_metrics_recorded('Controller/Rack/RenamedTxn')
    end

    def test_params_are_not_captured_with_capture_params_disabled
      with_config(:capture_params => false) do
        get('/grape_ape/10')

        expected = {}

        assert_equal expected, last_transaction_trace_request_params
      end
    end

    def test_route_params_are_captured
      with_config(:capture_params => true) do
        get('/grape_ape/10')

        expected = {
          'request.parameters.id' => '10'
        }

        assert_equal expected, last_transaction_trace_request_params
      end
    end

    def test_query_params_are_captured
      with_config(:capture_params => true) do
        get('/grape_ape?q=1234&foo=bar')

        expected = {
          'request.parameters.q' => '1234',
          'request.parameters.foo' => 'bar'
        }

        assert_equal expected, last_transaction_trace_request_params
      end
    end

    def test_post_body_params_are_captured
      with_config(:capture_params => true) do
        post('/grape_ape', {'q' => '1234', 'foo' => 'bar'}.to_json, 'CONTENT_TYPE' => 'application/json')

        expected = {
          'request.parameters.q' => '1234',
          'request.parameters.foo' => 'bar'
        }

        assert_equal expected, last_transaction_trace_request_params
      end
    end

    def test_post_body_params_are_captured_with_error
      with_config(:capture_params => true) do
        assert_raises(GrapeTestApiError) do
          post('/grape_ape_fail', {'q' => '1234', 'foo' => 'fail'}.to_json, 'CONTENT_TYPE' => 'application/json')
        end

        agent_attributes = attributes_for(last_traced_error, :agent)

        assert_equal('1234', agent_attributes['request.parameters.q'])
        assert_equal('fail', agent_attributes['request.parameters.foo'])
      end
    end

    def test_post_body_params_are_captured_with_rescue_from
      with_config(:capture_params => true) do
        post('/grape_ape_fail_rescue', {'q' => '1234', 'foo' => 'fail'}.to_json, 'CONTENT_TYPE' => 'application/json')

        agent_attributes = attributes_for(last_traced_error, :agent)

        assert_equal('1234', agent_attributes['request.parameters.q'])
        assert_equal('fail', agent_attributes['request.parameters.foo'])
      end
    end

    def test_post_body_with_nested_params_are_captured
      with_config(:capture_params => true) do
        params = {'ape' => {'first_name' => 'koko', 'last_name' => 'gorilla'}}
        post('/grape_ape', params.to_json, 'CONTENT_TYPE' => 'application/json')

        expected = {
          'request.parameters.ape.first_name' => 'koko',
          'request.parameters.ape.last_name' => 'gorilla'
        }

        assert_equal expected, last_transaction_trace_request_params
      end
    end

    def test_file_upload_params_are_filtered
      with_config(:capture_params => true) do
        params = {
          :title => 'blah',
          :file => Rack::Test::UploadedFile.new(__FILE__, 'text/plain')
        }
        post('/grape_ape', params)

        expected = {
          'request.parameters.title' => 'blah',
          'request.parameters.file' => '[FILE]'
        }

        assert_equal expected, last_transaction_trace_request_params
      end
    end

    def test_404_with_params_does_not_capture_them
      with_config(:capture_params => true) do
        post('/grape_catfish', {'foo' => 'bar'})
        expected = {}

        assert_equal expected, last_transaction_trace_request_params
      end
    end

    def test_params_are_captured_on_transaction_events
      with_config(:'attributes.include' => 'request.parameters.*',
        :'attributes.exclude' => ['request.*', 'response.*']) do
        json = {
          :foo => 'bar',
          :bar => 'baz'
        }.to_json

        post('/grape_ape', json, {'CONTENT_TYPE' => 'application/json'})

        expected = {'request.parameters.foo' => 'bar', 'request.parameters.bar' => 'baz'}
        actual = agent_attributes_for_single_event_posted_without_ignored_attributes

        assert_equal(expected, actual)
      end
    end

    def test_request_and_response_attributes_recorded_as_agent_attributes
      post('/grape_ape')

      expected = {
        'response.headers.contentLength' => last_response.content_length.to_i,
        'response.headers.contentType' => last_response.content_type,
        'request.headers.contentLength' => last_request.content_length.to_i,
        'request.headers.contentType' => last_request.content_type,
        'request.headers.host' => last_request.host,
        'request.method' => last_request.request_method,
        'request.uri' => last_request.path_info
      }
      actual = agent_attributes_for_single_event_posted_without_ignored_attributes

      # Rack >= 2.1 changes how/when contentLength is computed and Grape >= 1.3 also changes to deal with this.
      # interactions with Rack < 2.1 and >= 2.1 differ on response.headers.contentLength calculations
      # so we remove it when it is zero since its not present in such cases.
      #
      # Rack >= 3.1 further changes things, so we also excuse an actual 0 value
      # when it is in play
      if Gem::Version.new(::Grape::VERSION) >= Gem::Version.new('1.3.0')
        rack31_plus_and_zero = Rack.respond_to?(:release) &&
          Gem::Version.new(Rack.release) >= Gem::Version.new('3.1.0') &&
          actual['request.headers.contentLength'] == 0

        if expected['response.headers.contentLength'] == 0 || rack31_plus_and_zero
          expected.delete('response.headers.contentLength')
        end
      end

      assert_equal(expected, actual)
    end

    def test_distinct_routes_make_for_distinct_txn_names
      base_path = '/the/phantom/pain/'
      version = 'V'
      paths = %w[ocelot quiet]
      controller_class = 'FultonSheep'

      names = paths.each_with_object([]) do |path, arr|
        route = TestRoute.new(base_path + path, 'POST', version)
        arr << NewRelic::Agent::Instrumentation::Grape::Instrumentation.name_for_transaction(route, controller_class, nil)
      end

      assert_equal paths.size, names.uniq.size,
        'Expected there to be one unique transaction name per unique full route path'
    end
  end
end

class GrapeApiInstanceTest < Minitest::Test
  include Rack::Test::Methods
  include MultiverseHelpers

  setup_and_teardown_agent

  if ::Grape::VERSION >= '1.2.0'
    def app
      Rack::Builder.app { run(GrapeApiInstanceTestApi.new) }
    end

    def test_subclass_of_grape_api_instance
      get('/banjaxing')

      assert_metrics_recorded('Controller/Grape/GrapeApiInstanceTestApi/banjaxing (GET)')
    end
  end
end
