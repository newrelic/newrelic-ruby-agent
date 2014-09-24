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
# Note that instances of this class are intended to be append-only with respect
# to new metrics. That is, you should not attempt to *remove* an entry after it
# has been added, only update it (create a new instance if you need to start
# over with a blank slate).
#
# This class makes no provisions for safe usage from multiple threads, such
# measures should be externally provided.

require 'new_relic/agent/internal_agent_error'

module NewRelic
  module Agent
    class StatsHash < ::Hash

      attr_accessor :started_at, :harvested_at

      def initialize(started_at=Time.now)
        @started_at = started_at.to_f
        super() { |hash, key| hash[key] = NewRelic::Agent::Stats.new }
      end

      def marshal_dump
        [@started_at, Hash[self]]
      end

      def marshal_load(data)
        @started_at = data.shift
        self.merge!(data.shift)
      end

      def ==(other)
        Hash[self] == Hash[other]
      end

      class StatsHashLookupError < NewRelic::Agent::InternalAgentError
        def initialize(original_error, hash, metric_spec)
          super("Lookup error in StatsHash: #{original_error.class}: #{original_error.message}. Falling back adding #{metric_spec.inspect}")
        end
      end

      def record(metric_specs, value=nil, aux=nil, &blk)
        Array(metric_specs).each do |metric_spec|
          stats = nil
          begin
            stats = self[metric_spec]
          rescue NoMethodError => e
            # This only happen in the case of a corrupted default_proc
            # Side-step it manually, notice the issue, and carry on....
            NewRelic::Agent.instance.error_collector. \
              notice_agent_error(StatsHashLookupError.new(e, self, metric_spec))

            stats = NewRelic::Agent::Stats.new
            self[metric_spec] = stats

            # Try to restore the default_proc so we won't continually trip the error
            if respond_to?(:default_proc=)
              self.default_proc = Proc.new { |hash, key| hash[key] = NewRelic::Agent::Stats.new }
            end
          end

          stats.record(value, aux, &blk)
        end
      end

      def merge!(other)
        if other.is_a?(StatsHash) && other.started_at < @started_at
          @started_at = other.started_at
        end
        other.each do |key, val|
          merge_or_insert(key, val)
        end
        self
      end

      def merge_transaction_metrics!(txn_metrics, scope)
        txn_metrics.each_unscoped do |name, stats|
          spec = NewRelic::MetricSpec.new(name)
          merge_or_insert(spec, stats)
        end
        txn_metrics.each_scoped do |name, stats|
          spec = NewRelic::MetricSpec.new(name, scope)
          merge_or_insert(spec, stats)
        end
      end

      def merge_or_insert(metric_spec, stats)
        if self.has_key?(metric_spec)
          self[metric_spec].merge!(stats)
        else
          self[metric_spec] = stats
        end
      end
    end
  end
end
