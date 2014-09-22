# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/new_relic_service/marshaller'

module NewRelic
  module Agent
    class NewRelicService
      # Primitive Ruby Object Notation which complies JSON format data strutures
      class PrubyMarshaller < Marshaller
        def initialize
          ::NewRelic::Agent.logger.debug 'Using Pruby marshaller'
          warn_for_pruby_deprecation
        end

        def warn_for_pruby_deprecation
          if RUBY_VERSION < "1.9" && !defined?(::JSON)
            NewRelic::Agent.logger.warn("Upcoming versions of the Ruby agent running on Ruby 1.8.7 will require the 'json' gem. To avoid interuption in reporting, please update your Gemfile. See http://docs.newrelic.com/docs/ruby/ruby-1.8.7-support for more information.")
          end
        end

        def dump(ruby, opts={})
          NewRelic::LanguageSupport.with_cautious_gc do
            Marshal.dump(prepare(ruby, opts))
          end
        rescue => e
          ::NewRelic::Agent.logger.debug("#{e.class.name} : #{e.message} when marshalling #{ruby.inspect}")
          raise
        end

        def load(data)
          if data.nil? || data.empty?
            ::NewRelic::Agent.logger.error "Empty pruby response from collector: '#{data.inspect}'"
            return nil
          end

          NewRelic::LanguageSupport.with_cautious_gc do
            return_value(Marshal.load(data))
          end
        rescue
          ::NewRelic::Agent.logger.debug "Error encountered loading collector response: #{data}"
          raise
        end

        def format
          'pruby'
        end

        def self.is_supported?
          true
        end
      end
    end
  end
end
