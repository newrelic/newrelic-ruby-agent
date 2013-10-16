# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'rack'

module NewRelic::Rack
  # This middleware is used by the agent for the Real user monitoring (RUM)
  # feature, and will usually be automatically injected in the middleware chain.
  # If automatic injection is not working, you may manually use it in your
  # middleware chain instead.
  #
  # @api public
  #
  class BrowserMonitoring

    def initialize(app, options = {})
      @app = app
    end

    # method required by Rack interface
    def call(env)
      result = @app.call(env)   # [status, headers, response]

      if (NewRelic::Agent.browser_timing_header != "") && should_instrument?(env, result[0], result[1])
        response_string = autoinstrument_source(result[2], result[1])

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
      status == 200 &&
        !env[ALREADY_INSTRUMENTED_KEY] &&
        headers["Content-Type"] && headers["Content-Type"].include?("text/html") &&
        !headers['Content-Disposition'].to_s.include?('attachment')
    end

    X_UA_COMPATIBLE_RE = /<\s*meta[^>]+http-equiv=['"]x-ua-compatible['"][^>]*>/im.freeze

    def autoinstrument_source(response, headers)
      source = nil
      response.each {|fragment| source ? (source << fragment.to_s) : (source = fragment.to_s)}
      return nil unless source


      # Only scan the first 50k (roughly) then give up.
      beginning_of_source = source[0..50_000]
      # Don't scan for body close unless we find body start
      if (body_start = beginning_of_source.index("<body")) && (body_close = source.rindex("</body>"))

        footer = NewRelic::Agent.browser_timing_footer
        header = NewRelic::Agent.browser_timing_header

        match = X_UA_COMPATIBLE_RE.match(beginning_of_source)
        x_ua_compatible_position = match.end(0) if match

        head_pos = if x_ua_compatible_position
          # put after X-UA-Compatible meta tag if found
          ::NewRelic::Agent.logger.debug "Detected X-UA-Compatible meta tag. Attempting to insert RUM header after meta tag."
          x_ua_compatible_position
        elsif head_open = beginning_of_source.index("<head")
          ::NewRelic::Agent.logger.debug "Attempting to insert RUM header at beginning of head."
          # put at the beginning of the header
          beginning_of_source.index(">", head_open) + 1
        else
          ::NewRelic::Agent.logger.debug "Failed to detect head tag. Attempting to insert RUM header at above body tag."
          # otherwise put the header right above body start
          body_start
        end

        # check that head_pos is less than body close.  If it's not something
        # is really weird and we should punt.
        if head_pos && (head_pos < body_close)
          # rebuild the source
          source = source[0...head_pos] <<
            header <<
            source[head_pos...body_close] <<
            footer <<
            source[body_close..-1]
        else
          if head_pos
            ::NewRelic::Agent.logger.debug "Skipping RUM instrumentation. Failed to detect head tags."
          else
            ::NewRelic::Agent.logger.debug "Skipping RUM instrumentation. Detected head is after detected body close."
          end
        end
      end

      if headers['Content-Length']
        headers['Content-Length'] = calculate_content_length(source).to_s
      end

      source
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
