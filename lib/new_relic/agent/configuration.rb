# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/configuration/manager'

# The agent's configuration is accessed through a configuration object exposed
# by ::NewRelic::Agent.config.  It provides a hash like interface to the
# agent's settings.
#
# For example:
# ::NewRelic::Agent.config[:'transaction_tracer.enabled']
# determines whether transaction tracing is enabled.  String and symbol keys
# are treated indifferently and nested keys are collapsed and concatenated with
# a dot (i.e. {:a => {:b => 'c'} becomes { 'a.b' => 'c'}).
#
# The agent reads configuration from a variety of sources. These sources are
# modeled as a set of layers.  The top layer has the highest priority.  If the
# top layer does not contain the requested setting the config object will search
# through the subsequent layers returning the first value it finds.
#
# Configuration layers include EnvironmentSource (which reads settings from
# ENV), ServerSource (which reads Server Side Config from New Relic's servers),
# YamlSource (which reads from newrelic.yml),  ManualSource (which reads
# arguments passed to NewRelic::Agent.manual_start or potentially other
# methods), and Defaults (which contains default settings).
#
module NewRelic
  module Agent
    module Configuration
      # This can be mixed in with minimal impact to provide easy
      # access to the config manager
      module Instance
        def config
          @@manager ||= Manager.new
        end

        # for testing
        def reset_config
          @@manager = Manager.new
        end
      end

      class DottedHash < ::Hash
        def initialize(hash)
          self.merge!(dot_flattened(hash))
          keys.each do |key|
            self[(key.to_sym rescue key) || key] = delete(key)
          end
        end

        def inspect
          "#<#{self.class.name}:#{object_id} #{super}>"
        end

        def to_hash
          {}.replace(self)
        end

        protected
        # turns {'a' => {'b' => 'c'}} into {'a.b' => 'c'}
        def dot_flattened(nested_hash, names=[], result={})
          nested_hash.each do |key, val|
            next if val == nil
            if val.respond_to?(:has_key?)
              dot_flattened(val, names + [key], result)
            else
              result[(names + [key]).join('.')] = val
            end
          end
          result
        end
      end

      class ManualSource < DottedHash; end
    end
  end
end
