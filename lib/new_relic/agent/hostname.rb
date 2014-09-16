# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Hostname
      def self.get
        dyno_name = ENV['DYNO']
        if dyno_name && ::NewRelic::Agent.config[:'heroku.use_dyno_names']
          matching_prefix = heroku_dyno_name_prefix(dyno_name)
          dyno_name = "#{matching_prefix}.*" if matching_prefix
          dyno_name
        else
          Socket.gethostname
        end
      end

      MAX_HOST_LENGTH = 255

      # We want to let the agent use its cached copy of the hostname, so
      # don't do any defaulting or fallbacks in this method
      def self.get_display_host
        host = ::NewRelic::Agent.config[:'process_host.display_name']
        return unless host

        if host.length > MAX_HOST_LENGTH
          host = host[0...MAX_HOST_LENGTH]
          ::NewRelic::Agent.logger.warn("process_host.display_name setting is longer than allowed (#{MAX_HOST_LENGTH}). Value is being truncated to '#{host}'.")
        end
        host
      end

      def self.heroku_dyno_name_prefix(dyno_name)
        # TODO: Once the config transforms are in, protect this better in the
        # config layer itself. Allow CSV list, make sure we're an array, etc.
        dyno_prefixes = ::NewRelic::Agent.config[:'heroku.dyno_name_prefixes_to_shorten'] || []
        dyno_prefixes.find do |dyno_prefix|
          dyno_name.start_with?(dyno_prefix + ".")
        end
      end
    end
  end
end
