# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# A Hash-descended class for storing metric data in the NewRelic Agent.
#
# Keys are NewRelic::MetricSpec objects.
# Values are NewRelic::Agent::Stats objects.
#
# Missing keys will be automatically created as empty NewRelic::Agent::Stats
# instances, so use has_key? explicitly to check for key existence.
#
# This class makes no provisions for safe usage from multiple threads, such
# measures should be externally provided.

require 'new_relic/agent/internal_agent_error'

module NewRelic
  module Agent
    class StatsHash < ::Hash
      attr_accessor :harvested_at

      def initialize
        super { |hash, key| hash[key] = NewRelic::Agent::Stats.new }
      end

      def marshal_dump
        Hash[self]
      end

      def marshal_load(hash)
        self.merge!(hash)
      end

      def ==(other)
        Hash[self] == Hash[other]
      end

      class CorruptedDefaultProcError < NewRelic::Agent::InternalAgentError
        def initialize(hash, metric_spec)
          super("Corrupted default proc for StatsHash. Falling back adding #{metric_spec.inspect}")
        end
      end

      def record(metric_specs, value=nil, aux=nil)
        Array(metric_specs).each do |metric_spec|
          stats = nil
          begin
            stats = self[metric_spec]
          rescue => e
            # This only happen in the case of a corrupted default_proc
            # Side-step it manually, notice the issue, and carry on....
            NewRelic::Agent.instance.error_collector. \
              notice_agent_error(CorruptedDefaultProcError.new(self, metric_spec))

            stats = NewRelic::Agent::Stats.new
            self[metric_spec] = stats

            # Try to restore the default_proc so we won't continually trip the error
            if respond_to?(:default_proc=)
              self.default_proc = Proc.new { |hash, key| hash[key] = NewRelic::Agent::Stats.new }
            end
          end

          if block_given?
            yield stats
          else
            case value
            when Numeric
              aux ||= value
              stats.record_data_point(value, aux)
            when :apdex_s, :apdex_t, :apdex_f
              stats.record_apdex(value, aux)
            when NewRelic::Agent::Stats
              stats.merge!(value)
            end
          end
        end
      end

      class StatsMergerError < NewRelic::Agent::InternalAgentError
        def initialize(key, destination, source, original_exception)
          super("Failure when merging stats '#{key}'. In Hash: #{destination.inspect_full}. Merging: #{source.inspect_full}. Original exception: #{original_exception.class} #{original_exception.message}")
          set_backtrace(original_exception.backtrace)
        end
      end

      def merge!(other)
        other.each do |key,val|
          begin
            if self.has_key?(key)
              self[key].merge!(val)
            else
              self[key] = val
            end
          rescue => err
            NewRelic::Agent.instance.error_collector. \
              notice_agent_error(StatsMergerError.new(key, self.fetch(key, nil), val, err))
          end
        end
        self
      end

      def resolve_scopes!(resolved_scope)
        placeholder = StatsEngine::SCOPE_PLACEHOLDER.to_s
        each_pair do |spec, stats|
          spec.scope = resolved_scope if spec.scope == placeholder
        end
      end
    end
  end
end
