# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'erb'

module NewRelic
  module Agent
    module BrowserToken

      def self.get_token(request)
        return nil unless request

        agent_flag = request.cookies['NRAGENT']
        if agent_flag and agent_flag.instance_of? String
          s = agent_flag.split("=")
          if s.length == 2
            if s[0] == "tk" && s[1]
              sanitized = sanitize_token(s[1])
              return nil unless sanitized
              ERB::Util.h(sanitized)
            end
          end
        else
          nil
        end
      end

      # Remove any non-alphanumeric characters from the token to avoid XSS attacks.
      def self.sanitize_token(token)
        if token.match(/[^a-zA-Z0-9]/)
          ::NewRelic::Agent.logger.log_once(:warn, :invalid_browser_token,
                                           "Invalid characters found in browser token.")
          nil
        else
          token
        end
      end
    end
  end
end
