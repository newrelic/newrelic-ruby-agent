# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'json'

module NewRelic
  module Agent
    # ServerlessHandlerEventSources - New Relic's language agent devs maintain
    # a cross-agent JSON map of all AWS resources with the potential to invoke
    # an AWS Lambda function by issuing it an event. This map is used to glean
    # source specific attributes while instrumenting the function's invocation.
    #
    # Given that the event arrives as a Ruby hash argument to the AWS Lambda
    # function, the JSON map's values need to be converted into arrays that can
    # be passed to `Hash#dig`. So a value such as `'records[0].name'` needs to
    # be converted to `['records', 0, 'name']`. This class's `.to_hash` method
    # yields the converted data.
    #
    # Furthermore, `.length` calls are converted to Ruby `#size` notation to
    # denote that a method call must be performed on the dug value.
    class ServerlessHandlerEventSources
      JSON_SOURCE = File.join(File.dirname(__FILE__), 'serverless_handler_event_sources.json')

      def self.to_hash
        hash = {}
        raw = JSON.parse(File.read('lib/new_relic/agent/serverless_handler_event_sources.json'))
        raw.each do |type, info|
          hash[type] = {'attributes' => {},
                        'name' => info['name'],
                        'required_keys' => []}
          info['attributes'].each { |attr, value| hash[type]['attributes'][attr] = transform(value) }
          info['required_keys'].each { |key| hash[type]['required_keys'].push(transform(key)) }
        end
        hash.freeze
      end

      def self.transform(value)
        value.gsub(/\[(\d+)\]/, '.\1').split('.').map do |e|
          if e.match?(/^\d+$/)
            e.to_i
          elsif e == 'length'
            '#size'
          else
            e
          end
        end
      end
    end
  end
end
