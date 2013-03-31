# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    # A singleton responsible for determining if the agent should start
    # monitoring.
    #
    # If the agent is in a monitored environment (e.g. production) it will
    # attempt to avoid starting at "inapproriate" times, for example in an IRB
    # session.  On Heroku, logs typically go to STDOUT so agent logs can spam
    # the console during interactive sessions.
    #
    # It should be possible to override Autostart logic can with an explicit
    # configuration, for example the NEWRELIC_ENABLE environment variable or
    # agent_enabled key in newrelic.yml
    module Autostart
      extend self

      def agent_should_start?
          # Don't autostart the agent if we're in IRB or Rails console.
          ( ! defined?(IRB) ) &&
          # Don't autostart the agent if the command used to invoke the process
          # is "rake". This tends to spam the console when people deploy to
          # heroku (where logs typically go to STDOUT).
          ( File.basename($0) != 'rake' )
      end


    end
  end
end
