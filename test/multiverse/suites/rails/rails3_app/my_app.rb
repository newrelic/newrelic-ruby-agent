# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# We define our single Rails application here, one time, upon the first inclusion
# Tests should feel free to define their own Controllers locally, but if they
# need anything special at the Application level, put it here
if !defined?(MyApp)
  ENV['NEW_RELIC_DISPATCHER'] = 'test'

  class NamedMiddleware
    def initialize(app, options = {})
      @app = app
    end

    def call(env)
      status, headers, body = @app.call(env)
      headers['NamedMiddleware'] = '1'
      [status, headers, body]
    end
  end

  class InstanceMiddleware
    attr_reader :name

    def initialize
      @app = nil
      @name = 'InstanceMiddleware'
    end

    def new(app)
      @app = app
      self
    end

    def call(env)
      status, headers, body = @app.call(env)
      headers['InstanceMiddleware'] = '1'
      [status, headers, body]
    end
  end

  if defined?(Sinatra)
    module Sinatra
      class Application < Base
        # Override to not accidentally start the app in at_exit handler
        set :run, proc { false }
      end
    end

    class SinatraTestApp < Sinatra::Base
      set :host_authorization, {permitted_hosts: []}
      get '/' do
        raise 'Intentional error' if params['raise']

        'SinatraTestApp#index'
      end
    end
  end

  class MyApp < Rails::Application
    # We need a secret token for session, cookies, etc.
    config.active_support.deprecation = :log
    config.secret_token = '49837489qkuweoiuoqwehisuakshdjksadhaisdy78o34y138974xyqp9rmye8yrpiokeuioqwzyoiuxftoyqiuxrhm3iou1hrzmjk'
    config.eager_load = false
    config.enable_reloading = false if Rails::VERSION::STRING >= '7.2'
    config.filter_parameters += [:secret]
    config.secret_key_base = fake_guid(64)
    if Rails::VERSION::STRING >= '7.0.0'
      config.action_controller.default_protect_from_forgery = true
    end
    if config.respond_to?(:hosts)
      config.hosts << 'www.example.com'
    end
    initializer 'install_error_middleware' do
      config.middleware.use(ErrorMiddleware)
    end
    initializer 'install_middleware_by_name' do
      config.middleware.use(NamedMiddleware)
    end
    initializer 'install_middleware_instance' do
      config.middleware.use(InstanceMiddleware.new)
    end
  end
  MyApp.initialize!

  test_controller_actions = {
    'bad_instrumentation' => %w[failwhale],
    'child' => %w[bar foo],
    'data' => %w[do_a_redirect exist_fragment expire_test_fragment halt_my_callback
      not_allowed read_test_fragment send_test_data send_test_file send_test_stream
      write_test_fragment],
    'error' => %w[controller_error error_with_custom_params exception_error frozen_error
      ignored_action ignored_error ignored_status_code middleware_error model_error
      noticed_error noticed_error_with_expected_error server_ignored_error
      string_noticed_error view_error],
    'gc' => %w[gc_action],
    'ignored' => %w[action_not_ignored action_to_ignore action_to_ignore_apdex],
    'live' => %w[brains],
    'parameter_capture' => %w[error sql transaction],
    'queue' => %w[nested queued],
    'request_stats' => %w[stats_action stats_action_with_custom_params],
    'transaction_ignorer' => %w[run_transaction],
    'undead' => %w[brain_stream brains],
    'views' => %w[collection_render deep_partial_render file_render haml_render
      inline_render js_render json_render no_template nothing_render raise_render
      render_with_delays template_render_with_3_partial_renders text_render xml_render]
  }

  MyApp.routes.draw do
    get('/bad_route' => 'test#controller_error',
      :constraints => lambda do |_|
        raise ActionController::RoutingError.new('this is an uncaught routing error')
      end)

    mount SinatraTestApp, :at => '/sinatra_app' if defined?(Sinatra)

    post '/filtering_test' => FilteringTestApp.new

    post '/parameter_capture', :to => 'parameter_capture#create'

    get '/view_components', :to => 'view_component#index' # This app and route is used in ViewComponent tests

    test_controller_actions.each do |controller, actions|
      actions.each do |action|
        get "/#{controller}/#{action}(/:id)", :to => "#{controller}##{action}"
      end
    end
  end

  class ApplicationController < ActionController::Base
    if Rails::VERSION::STRING.to_i >= 7
      # forgery protection explicitly prevents application/javascript content types
      # as originating from the same origin
      # this allows view_instrumentation_test to pass
      skip_before_action :verify_authenticity_token, only: :js_render
    end

    # The :text option to render was deprecated in Rails 4.1 in favor of :body.
    # With the patch below we can write our tests using render :body but have
    # that converted to render :text for Rails versions that do not support
    # render :body.
    if Rails::VERSION::STRING < '4.1.0'
      def render(*args)
        options = args.first
        if Hash === options && options.key?(:body)
          options[:text] = options.delete(:body)
        end
        super
      end
    end
  end
end
