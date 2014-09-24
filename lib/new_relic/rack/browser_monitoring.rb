# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'rack'
require 'new_relic/rack/agent_middleware'
require 'new_relic/agent/instrumentation/middleware_proxy'

module NewRelic::Rack
  # This middleware is used by the agent for the Real user monitoring (RUM)
  # feature, and will usually be automatically injected in the middleware chain.
  # If automatic injection is not working, you may manually use it in your
  # middleware chain instead.
  #
  # @api public
  #
  class BrowserMonitoring < AgentMiddleware
    # The maximum number of bytes of the response body that we will
    # examine in order to look for a RUM insertion point.
    SCAN_LIMIT = 50_000

    def traced_call(env)
      result = @app.call(env)   # [status, headers, response]

      js_to_inject = NewRelic::Agent.browser_timing_header
      if (js_to_inject != "") && should_instrument?(env, result[0], result[1])
        response_string = autoinstrument_source(result[2], result[1], js_to_inject)

        env[ALREADY_INSTRUMENTED_KEY] = true
        if response_string
          response = Rack::Response.new(response_string, result[0], result[1])
          response.finish
        else
          result
        end
      else
        result
      end
    end

    ALREADY_INSTRUMENTED_KEY = "newrelic.browser_monitoring_already_instrumented"

    def should_instrument?(env, status, headers)
      NewRelic::Agent.config[:'browser_monitoring.auto_instrument'] &&
        status == 200 &&
        !env[ALREADY_INSTRUMENTED_KEY] &&
        is_html?(headers) &&
        !is_attachment?(headers) &&
        !is_streaming?(env)
    end

    def is_html?(headers)
      headers["Content-Type"] && headers["Content-Type"].include?("text/html")
    end

    def is_attachment?(headers)
      headers['Content-Disposition'].to_s.include?('attachment')
    end

    def is_streaming?(env)
      return false unless defined?(ActionController::Live)

      env['action_controller.instance'].class.included_modules.include?(ActionController::Live)
    end

    CHARSET_RE         = /<\s*meta[^>]+charset\s*=[^>]*>/im.freeze
    X_UA_COMPATIBLE_RE = /<\s*meta[^>]+http-equiv\s*=\s*['"]x-ua-compatible['"][^>]*>/im.freeze

    def autoinstrument_source(response, headers, js_to_inject)
      source = gather_source(response)
      close_old_response(response)
      return nil unless source

      # Only scan the first 50k (roughly) then give up.
      beginning_of_source = source[0..SCAN_LIMIT]

      if body_start = find_body_start(beginning_of_source)
        meta_tag_positions = [
          find_x_ua_compatible_position(beginning_of_source),
          find_charset_position(beginning_of_source)
        ].compact

        if !meta_tag_positions.empty?
          insertion_index = meta_tag_positions.max
        else
          insertion_index = find_end_of_head_open(beginning_of_source) || body_start
        end

        if insertion_index
          source = source[0...insertion_index] <<
            js_to_inject <<
            source[insertion_index..-1]
        else
          NewRelic::Agent.logger.debug "Skipping RUM instrumentation. Could not properly determine location to inject script."
        end
      else
        msg = "Skipping RUM instrumentation. Unable to find <body> tag in first #{SCAN_LIMIT} bytes of document."
        NewRelic::Agent.logger.log_once(:warn, :rum_insertion_failure, msg)
        NewRelic::Agent.logger.debug(msg)
      end

      if headers['Content-Length']
        headers['Content-Length'] = calculate_content_length(source).to_s
      end

      source
    rescue => e
      NewRelic::Agent.logger.debug "Skipping RUM instrumentation on exception.", e
      nil
    end

    def gather_source(response)
      source = nil
      response.each {|fragment| source ? (source << fragment.to_s) : (source = fragment.to_s)}
      source
    end

    # Per "The Response > The Body" section of Rack spec, we should close
    # if our response is able. http://rack.rubyforge.org/doc/SPEC.html
    def close_old_response(response)
      if response.respond_to?(:close)
        response.close
      end
    end

    def find_body_start(beginning_of_source)
      beginning_of_source.index("<body")
    end

    def find_x_ua_compatible_position(beginning_of_source)
      match = X_UA_COMPATIBLE_RE.match(beginning_of_source)
      match.end(0) if match
    end

    def find_charset_position(beginning_of_source)
      match = CHARSET_RE.match(beginning_of_source)
      match.end(0) if match
    end

    def find_end_of_head_open(beginning_of_source)
      head_open = beginning_of_source.index("<head")
      beginning_of_source.index(">", head_open) + 1 if head_open
    end

    # String does not respond to 'bytesize' in 1.8.6. Fortunately String#length
    # returns bytes rather than characters in 1.8.6 so we can use that instead.
    def calculate_content_length(source)
      if source.respond_to?(:bytesize)
        source.bytesize
      else
        source.length
      end
    end
  end
end
