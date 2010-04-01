require 'fileutils'

module NewRelic
  module Rack
    class Episodes
      
      BEACON_URL = "/newrelic/episodes/page_load"
      def initialize(app)
        @app = app
      end
      def call(env)
#        env.each.to_a.sort_by(&:first).each do | k, v |
#        puts "      '#{'%-28s'%k}' => '#{v}'"
#        end
        path = env["REQUEST_PATH"].to_s.squeeze("/")
        NewRelic::Agent.logger.info "Path = '#{path}'"
        if path.index(BEACON_URL) == 0
          @request = ::Rack::Request.new(env)
          @response = ::Rack::Response.new([],204)
          process
        else
          @app.call(env)
        end
      end

      private

      def process
        measures = @request['ets'].split(',').map { |str| str.split(':') }
        url = @request['url']
        if false and defined?(::ActionController::Routing::Routes)
          params = ::ActionController::Routing::Routes.recognize_path(url) rescue {}
          controller, action = params.values_at :controller, :action
        end

        NewRelic::Agent.logger.debug "Capturing measures from #{url} (#{controller}##{action}):\n   #{measures.inspect}"
        measures.each do | name, value |
          metric_name = "Client/#{name}"
          NewRelic::Agent.instance.stats_engine.get_stats_no_scope(metric_name).record_data_point(value.to_f / 1000.0)
        end
        @response.finish
      end
    end
  end
end
