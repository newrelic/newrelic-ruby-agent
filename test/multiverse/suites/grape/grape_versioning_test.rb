# encoding: utf-8
# This file is distributed under New Relic"s license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

unless ::Grape::VERSION == '0.1.5'
  require 'multiverse_helpers'
  require './grape_versioning_test_api'

  require File.join(File.dirname(__FILE__), "..", "..", "..", "agent_helper")

  class GrapeVersioningTest < Minitest::Test
    include Rack::Test::Methods
    include MultiverseHelpers

    setup_and_teardown_agent

    def app
      Rack::Builder.app { run GrapeVersioning::TestApi.new }
    end

    def test_version_from_path_is_recorded_in_transaction_name
      get '/v1/fish'
      assert_metrics_recorded('Controller/Grape/GrapeVersioning::TestApi/v1/fish (GET)')
    end

    def test_when_using_version_from_param_version_is_not_recorded_in_transaction_name
      get '/fish?apiver=v2'
      assert_metrics_recorded('Controller/Grape/GrapeVersioning::TestApi/fish (GET)')
    end

    def test_when_using_version_from_header_is_not_recorded_in_transaction_name
      get '/fish', nil, 'HTTP_ACCEPT' => "application/vnd.newrelic-v3+json"
      assert_metrics_recorded('Controller/Grape/GrapeVersioning::TestApi/fish (GET)')
    end

    def test_when_using_version_from_accept_version_header_is_not_recorded_in_transaction_name
      get '/fish', nil, 'HTTP_ACCEPT_VERSION' => 'v4'
      assert_metrics_recorded('Controller/Grape/GrapeVersioning::TestApi/fish (GET)')
    end
  end
end
