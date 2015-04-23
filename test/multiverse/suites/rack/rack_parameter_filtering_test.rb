# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'filtering_test_app'

if NewRelic::Agent::Instrumentation::RackHelpers.rack_version_supported?

  class RackParameterFilteringTest < Minitest::Test
    include MultiverseHelpers

    setup_and_teardown_agent

    include Rack::Test::Methods

    def app
      Rack::Builder.app { run FilteringTestApp.new }
    end

    def test_file_upload_params_are_filtered
      with_config(:capture_params => true) do
        params = {
          :title => "blah",
          :file => Rack::Test::UploadedFile.new(__FILE__, 'text/plain')
        }
        post '/', params

        expected = {
          "request.parameters.title" => "blah",
          "request.parameters.file" => "[FILE]"
        }
        assert_equal expected, last_transaction_trace_request_params
      end
    end

    def test_apply_filters_returns_params_when_rails_is_not_present
      with_config(:capture_params => true) do
        params = {"name" => "name", "password" => "mypass"}
        post '/', params

        expected = {
          "request.parameters.name" => "name",
          "request.parameters.password" => "mypass"
        }
        assert_equal expected, last_transaction_trace_request_params
      end
    end
  end
end
