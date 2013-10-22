# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/language_support'

module NewRelic
  module Agent
    class StatsEngine
      # Handles methods related to actual Metric collection
      module MetricStats
        SCOPE_PLACEHOLDER = :__SCOPE__

        # Lookup and write to the named metric in a single call.
        #
        # This method is thead-safe, and is preferred to the lookup / modify
        # method pairs (e.g. get_stats + record_data_point)
        #
        # @api private
        def record_metrics(metric_names_or_specs, value=nil, options={}, &blk)
          scoped = options[:scoped]
          scope = in_transaction? ? SCOPE_PLACEHOLDER : nil
          effective_scope = scoped && scope

          specs = coerce_to_metric_spec_array(metric_names_or_specs, effective_scope)

          if in_transaction?
            transaction_stats_hash.record(specs, value, &blk)
          else
            with_stats_lock do
              @stats_hash.record(specs, value, &blk)
            end
          end
        end

        # Fast-path version of the #record_metrics version above, used in
        # performance-sensitive code paths
        #
        # metric_specs must be an Array of MetricSpec objects
        # value and aux are passed directly to the corresponding parameters of
        # StatsHash#record
        #
        # @api private
        def record_metrics_internal(metric_specs, value, aux)
          tsh = transaction_stats_hash
          if tsh
            tsh.record(metric_specs, value, aux)
          else
            with_stats_lock do
              @stats_hash.record(metric_specs, value, aux)
            end
          end
        end

        # a simple accessor for looking up a stat with no scope -
        # returns a new stats object if no stats object for that
        # metric exists yet
        def get_stats_no_scope(metric_name)
          get_stats(metric_name, false)
        end

        # If scoped_metric_only is true, only a scoped metric is created (used by rendering metrics which by definition are per controller only)
        # Leaving second, unused parameter for compatibility
        def get_stats(metric_name, _ = true, scoped_metric_only = false, scope = nil)
          stats = nil
          with_stats_lock do
            if scoped_metric_only
              stats = @stats_hash[NewRelic::MetricSpec.new(metric_name, scope)]
            else
              unscoped_spec = NewRelic::MetricSpec.new(metric_name)
              unscoped_stats = @stats_hash[unscoped_spec]
              if scope && scope != metric_name
                scoped_spec = NewRelic::MetricSpec.new(metric_name, scope)
                scoped_stats = @stats_hash[scoped_spec]
                stats = NewRelic::Agent::ChainedStats.new(scoped_stats, unscoped_stats)
              else
                stats = unscoped_stats
              end
            end
          end
          stats
        end

        # Returns a stat if one exists, otherwise returns nil. If you
        # want auto-initialization, use one of get_stats or get_stats_no_scope
        def lookup_stats(metric_name, scope_name = '')
          spec = NewRelic::MetricSpec.new(metric_name, scope_name)
          with_stats_lock do
            @stats_hash.has_key?(spec) ? @stats_hash[spec] : nil
          end
        end

        # Helper method for timing supportability metrics
        def record_supportability_metric_timed(metric)
          start_time = Time.now
          yield
        ensure
          duration = (Time.now - start_time).to_f
          record_supportability_metric(metric, duration)
        end

        # Helper for recording a straight value into the count
        def record_supportability_metric_count(metric, value)
          record_supportability_metric(metric) do |stat|
            stat.call_count = value
          end
        end

        # Helper method for recording supportability metrics consistently
        def record_supportability_metric(metric, value=nil)
          real_name = "Supportability/#{metric}"
          if block_given?
            record_metrics(real_name) { |stat| yield stat }
          else
            record_metrics(real_name, value)
          end
        end

        def reset_stats
          with_stats_lock do
            old = @stats_hash
            @stats_hash = StatsHash.new
            old
          end
        end

        # merge data from previous harvests into this stats engine
        def merge!(other_stats_hash)
          with_stats_lock do
            @stats_hash.merge!(other_stats_hash)
          end
        end

        def harvest
          now = Time.now
          snapshot = reset_stats
          snapshot = apply_rules_to_metric_data(@metric_rules, snapshot)
          snapshot.harvested_at = now
          snapshot
        end

        def apply_rules_to_metric_data(rules_engine, stats_hash)
          renamed_stats = NewRelic::Agent::StatsHash.new
          stats_hash.each do |spec, stats|
            new_name = rules_engine.rename(spec.name)
            new_spec = NewRelic::MetricSpec.new(new_name, spec.scope)
            renamed_stats[new_spec].merge!(stats)
          end
          renamed_stats
        end

        def coerce_to_metric_spec_array(metric_names_or_specs, scope)
          specs = []
          Array(metric_names_or_specs).map do |name_or_spec|
            case name_or_spec
            when String
              specs << NewRelic::MetricSpec.new(name_or_spec)
              specs << NewRelic::MetricSpec.new(name_or_spec, scope) if scope
            when NewRelic::MetricSpec
              specs << name_or_spec
            end
          end
          specs
        end

        # For use by test code only.
        def clear_stats
          reset_stats
          NewRelic::Agent::BusyCalculator.reset
        end

        # Returns all of the metric names of all the stats in the engine.
        # For use by test code only.
        def metrics
          with_stats_lock do
            @stats_hash.keys.map { |spec| spec.to_s }
          end
        end

        def metric_specs
          with_stats_lock { @stats_hash.keys }
        end

        def in_transaction?
          !!transaction_stats_hash
        end
      end
    end
  end
end
