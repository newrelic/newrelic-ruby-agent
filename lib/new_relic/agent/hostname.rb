# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Hostname
      def self.get
        dyno_name = ENV['DYNO']
        if dyno_name && ::NewRelic::Agent.config[:'heroku.use_dyno_names']
          dyno_name
        else
          Socket.gethostname
        end
      end
    end
  end
end
