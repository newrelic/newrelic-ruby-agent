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
    class StatsHash

      attr_accessor :started_at, :harvested_at

      def initialize(started_at=Time.now)
        @started_at = started_at.to_f
        @scoped     = Hash.new { |h, k| h[k] = NewRelic::Agent::Stats.new }
        @unscoped   = Hash.new { |h, k| h[k] = NewRelic::Agent::Stats.new }
      end

      def marshal_dump
        [@started_at, Hash[@scoped], Hash[@unscoped]]
      end

      def marshal_load(data)
        @started_at = data.shift
        @scoped   = Hash.new { |h, k| h[k] = NewRelic::Agent::Stats.new }
        @unscoped = Hash.new { |h, k| h[k] = NewRelic::Agent::Stats.new }
        @scoped.merge!(data.shift)
        @unscoped.merge!(data.shift)
      end

      def ==(other)
        self.to_h == other.to_h
      end

      def to_h
        hash = {}
        @scoped.each   { |k, v| hash[k] = v }
        @unscoped.each { |k, v| hash[NewRelic::MetricSpec.new(k)] = v }
        hash
      end

      def [](key)
        case key
        when String
          @unscoped[key]
        when NewRelic::MetricSpec
          if key.scope.empty?
            @unscoped[key.name]
          else
            @scoped[key]
          end
        end
      end

      def each
        @scoped.each do |k, v|
          yield k, v
        end
        @unscoped.each do |k, v|
          spec = NewRelic::MetricSpec.new(k)
          yield spec, v
        end
      end

      def empty?
        @unscoped.empty? && @scoped.empty?
      end

      def size
        @unscoped.size + @scoped.size
      end

      def to_h
        Hash[self]
      end

      class StatsHashLookupError < NewRelic::Agent::InternalAgentError
        def initialize(original_error, hash, metric_spec)
          super("Lookup error in StatsHash: #{original_error.class}: #{original_error.message}. Falling back adding #{metric_spec.inspect}")
        end
      end

      def record(metric_specs, value=nil, aux=nil, &blk)
        Array(metric_specs).each do |metric_spec|
          if metric_spec.scope.empty?
            stats = @unscoped[metric_spec.name]
          else
            stats = @scoped[metric_spec]
          end
          stats.record(value, aux, &blk)
        end
      end

      def merge!(other)
        if other.is_a?(StatsHash) && other.started_at < @started_at
          @started_at = other.started_at
        end
        other.each do |spec, val|
          if spec.scope.empty?
            merge_or_insert(@unscoped, spec.name, val)
          else
            merge_or_insert(@scoped, spec, val)
          end
        end
        self
      end

      def merge_transaction_metrics!(txn_metrics, scope)
        txn_metrics.each_unscoped do |name, stats|
          merge_or_insert(@unscoped, name, stats)
        end
        txn_metrics.each_scoped do |name, stats|
          spec = NewRelic::MetricSpec.new(name, scope)
          merge_or_insert(@scoped, spec, stats)
        end
      end

      def merge_or_insert(target, name, stats)
        if target.has_key?(name)
          target[name].merge!(stats)
        else
          target[name] = stats
        end
      end
    end
  end
end
