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
              ERB::Util.h(sanitize_token(s[1]))
            end
          end
        else
          nil
        end
      end

      # Run through a collection of unsafe characters ( in the context of the token )
      # and set the token to an empty string if any of them are found in the token so that
      # potential XSS attacks via the token are avoided
      def self.sanitize_token(token)
        if ( /[<>'"]/ =~ token )
          token.replace("")
        end
        token
      end
    end
  end
end
