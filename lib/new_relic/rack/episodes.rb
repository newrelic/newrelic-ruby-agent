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
        NewRelic::Agent.logger.debug "Episodes middleware sees '#{path}'"
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
        user_agent = @request['userAgent']
        if defined?(::ActionController::Routing::Routes)
          routes = ::ActionController::Routing::Routes
          params = routes.recognize_path(url, :method => :get) rescue {}
          controller, action = params.values_at :controller, :action
          scope_name = "Controller/#{controller}/#{action}" if controller && action
        end
        
        NewRelic::Agent.logger.debug "Capturing measures from #{url} (#{scope_name}):\n   #{measures.inspect}"
        measures.each do | name, value |
          metric_name = "Client/#{name}"
          seconds_value = value.to_f / 1000.0
          # We capture summary metrics for all controllers
          NewRelic::Agent.instance.stats_engine.get_stats_no_scope(metric_name).record_data_point(seconds_value)
          
          # We capture summary metrics for browser/os dimensions blamed to the controllers.
          if user_agent
            browser, version, os = identify_browser_and_os(user_agent)
            browser_metric_name = "Client/#{name}/#{os}/#{browser}/#{version}"
            NewRelic::Agent.instance.stats_engine.get_stats(browser_metric_name, true, false, scope_name).record_data_point(seconds_value)
          end
        end
        @response.finish
      end
      
      def identify_browser_and_os(user_agent)
        user_agent = user_agent.downcase
        
        # tests for browser version
        # for safari and firefox we take the major and minor version - e.g. Firefox 2.1 or Safari 4.0
        # for all other browsers we take only the major version - e.g. IE 7, Chrome 3
        
        case user_agent
        when /opera/
          browser = 'Opera'
          version = ($1 || 0).to_i if user_agent[/opera(?:.*version)?[ \/](\d+)\./]
        when /chrome(?:\/(\d+)\.)?/  # chrome must go before safari
          browser = 'Chrome'
          version = ($1 || 0).to_i
        when /safari|applewebkit\//
          browser = 'Safari'
          version = $1.to_f if user_agent[/version\/(\d+\.\d+)/] # safari used Version/* starting from 3.0
        when /msie (\d+)\./
          browser = 'IE'
          version = $1.to_i
        else if user_agent[/compatible/].nil? 
          if user_agent[/like firefox\//].nil? && user_agent[/firefox\//]
            browser = 'Firefox'
            version = $1.to_f if user_agent[/firefox\/(\d+\.\d+)/]
          elsif user_agent[/gecko\/?/]
            browser = 'Mozilla Gecko'
            version = $1.to_f if user_agent[/rv:(\d+\.\d+)/]
          end
        end
      end
      
      if user_agent[/windows/]
        os = 'Windows'
      elsif user_agent[/iphone/] # iphone must go before mac
        os = 'iPhone'
      elsif user_agent[/macintosh|mac os/]
        os = 'Mac'
      elsif user_agent[/linux/]
        os = 'Linux'
      end
      
      return browser || 'Unknown', version || 0, os || 'Unknown'
    end
    
  end
end
end
