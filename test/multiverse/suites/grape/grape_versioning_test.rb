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
    if NewRelic::VersionNumber.new(Grape::VERSION) >= NewRelic::VersionNumber.new('0.16.0')
      def test_version_from_accept_version_header_is_recorded_in_transaction_name
        @app_class = GrapeVersioning::ApiV4
        get '/fish', {}, 'HTTP_ACCEPT_VERSION' => 'v4'
        assert_metrics_recorded('Controller/Grape/GrapeVersioning::ApiV4-v4/fish (GET)')
      end

      def test_version_from_accept_version_header_is_recorded_in_transaction_name_cascading_versions_penultimate
        @app_class = GrapeVersioning::CascadingAPI
        get '/fish', {}, 'HTTP_ACCEPT_VERSION' => 'v4'
        assert_metrics_recorded('Controller/Grape/GrapeVersioning::CascadingAPI-v4/fish (GET)')
      end

      def test_version_from_accept_version_header_is_recorded_in_transaction_name_cascading_versions_latest
        @app_class = GrapeVersioning::CascadingAPI
        get '/fish', {}, 'HTTP_ACCEPT_VERSION' => 'v5'
        assert_metrics_recorded('Controller/Grape/GrapeVersioning::CascadingAPI-v5/fish (GET)')
      end
    end

    def test_app_not_using_versioning_does_not_record_version_in_transaction_name
      @app_class = GrapeVersioning::Unversioned
      get '/fish'
      assert_metrics_recorded('Controller/Grape/GrapeVersioning::Unversioned/fish (GET)')
    end

    def test_shared_version_declaration_in_tranasaction_names
      @app_class = GrapeVersioning::SharedApi
      %w[ v1 v2 v3 v4 ].each do |v|
        get "/#{v}/fish"
        assert_metrics_recorded("Controller/Grape/GrapeVersioning::SharedApi-#{v}/fish (GET)")
      end
    end

    def test_shared_version_block_in_tranasaction_names
      @app_class = GrapeVersioning::SharedBlockApi
      %w[ v1 v2 v3 v4 ].each do |v|
        get "/#{v}/fish"
        assert_metrics_recorded("Controller/Grape/GrapeVersioning::SharedBlockApi-#{v}/fish (GET)")
      end
    end

    # see instrumentation/grape.rb:41
    #
    # <= 0.15 - route.route_version #=> String
    # >= 0.16 - route.version #=> Array
    #
    # defaulting without version/vendor in Accept value does not set rack.env['api.version']
    #
    def test_default_header_version_in_tranasaction_names
      @app_class = GrapeVersioning::DefaultHeaderApi
      get "/fish", nil, 'HTTP_ACCEPT' => 'application/json'
      assert_metrics_recorded("Controller/Grape/GrapeVersioning::DefaultHeaderApi-v2|v3/fish (GET)")
    end

    # :accept_version_header introduced in 0.5
    #
    # defaulting with header key/empty value does not set rack.env['api.version']
    #
    if NewRelic::VersionNumber.new(Grape::VERSION) >= NewRelic::VersionNumber.new('0.5.0')
      def test_default_accept_version_header_version_in_tranasaction_names
        @app_class = GrapeVersioning::DefaultAcceptVersionHeaderApi
        get "/fish", nil, 'HTTP_ACCEPT_VERSION' => ''
        assert_metrics_recorded("Controller/Grape/GrapeVersioning::DefaultAcceptVersionHeaderApi-v2|v3/fish (GET)")
      end
    end

  end
end
