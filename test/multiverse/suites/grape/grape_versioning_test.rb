# encoding: utf-8
# This file is distributed under New Relic"s license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

unless ::Grape::VERSION == '0.1.5'
  require './grape_versioning_test_api'

  class GrapeVersioningTest < Minitest::Test
    include Rack::Test::Methods
    include MultiverseHelpers

    setup_and_teardown_agent

    def app
      clazz = @app_class
      Rack::Builder.app { run clazz.new }
    end

    def test_version_from_path_is_recorded_in_transaction_name
      @app_class = GrapeVersioning::ApiV1
      get '/v1/fish'
      assert_metrics_recorded('Controller/Grape/GrapeVersioning::ApiV1-v1/fish (GET)')
    end

    def test_version_is_stripped_when_requesting_root_route
      @app_class = GrapeVersioning::ApiV1
      get '/v1'
      assert_metrics_recorded('Controller/Grape/GrapeVersioning::ApiV1-v1/ (GET)')
    end

    def test_version_is_stripped_when_requesting_root_route_with_trailing_slash
      @app_class = GrapeVersioning::ApiV1
      get '/v1/'
      assert_metrics_recorded('Controller/Grape/GrapeVersioning::ApiV1-v1/ (GET)')
    end

    def test_version_from_param_version_is_recorded_in_transaction_name
      @app_class = GrapeVersioning::ApiV2
      get '/fish?apiver=v2'
      assert_metrics_recorded('Controller/Grape/GrapeVersioning::ApiV2-v2/fish (GET)')
    end

    def test_version_from_header_is_recorded_in_transaction_name
      @app_class = GrapeVersioning::ApiV3
      get '/fish', {}, 'HTTP_ACCEPT' => 'application/vnd.newrelic-v3+json'
      assert_metrics_recorded('Controller/Grape/GrapeVersioning::ApiV3-v3/fish (GET)')
    end

    #version from http accept header is not supported in older versions of grape
    if NewRelic::VersionNumber.new(Grape::VERSION) >= NewRelic::VersionNumber.new('4.0.0')
      def test_version_from_accept_version_header_is_recorded_in_transaction_name
        @app_class = GrapeVersioning::ApiV4
        get '/fish', {}, 'HTTP_ACCEPT_VERSION' => 'v4'
        assert_metrics_recorded('Controller/Grape/GrapeVersioning::ApiV4-v4/fish (GET)')
      end
    end

    def test_app_not_using_versioning_does_not_record_version_in_transaction_name
      @app_class = GrapeVersioning::Unversioned
      get '/fish'
      assert_metrics_recorded('Controller/Grape/GrapeVersioning::Unversioned/fish (GET)')
    end
  end
end
