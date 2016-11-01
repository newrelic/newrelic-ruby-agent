# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Hostname
      def self.get
        dyno_name = ENV['DYNO']
        @hostname ||= if dyno_name && ::NewRelic::Agent.config[:'heroku.use_dyno_names']
          matching_prefix = heroku_dyno_name_prefix(dyno_name)
          dyno_name = "#{matching_prefix}.*" if matching_prefix
          dyno_name
        else
          Socket.gethostname
        end
      end

      def self.heroku_dyno_name_prefix(dyno_name)
        get_dyno_prefixes.find do |dyno_prefix|
          dyno_name.start_with?(dyno_prefix + ".")
        end
      end

      def self.get_dyno_prefixes
        ::NewRelic::Agent.config[:'heroku.dyno_name_prefixes_to_shorten']
      end

      LOCALHOST = %w[
        localhost
        0.0.0.0
        127.0.0.1
        0:0:0:0:0:0:0:1
        0:0:0:0:0:0:0:0
        ::1
        ::
      ].freeze

      def self.local? host_or_ip
        LOCALHOST.include?(host_or_ip)
      end

      def self.get_external host_or_ip
        local?(host_or_ip) ? get : host_or_ip
      end
    end
  end
end
