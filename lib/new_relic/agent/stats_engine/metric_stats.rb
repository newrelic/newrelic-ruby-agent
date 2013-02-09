require 'new_relic/language_support'

module NewRelic
  module Agent
    class StatsEngine
      # Handles methods related to actual Metric collection
      module MetricStats
        # a simple accessor for looking up a stat with no scope -
        # returns a new stats object if no stats object for that
        # metric exists yet
        def get_stats_no_scope(metric_name)
          get_stats(metric_name, false)
        end

        # If use_scope is true, two chained metrics are created, one with scope and one without
        # If scoped_metric_only is true, only a scoped metric is created (used by rendering metrics which by definition are per controller only)
        def get_stats(metric_name, use_scope = true, scoped_metric_only = false, scope = nil)
          scope ||= scope_name if use_scope
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
                stats = NewRelic::ChainedStats.new(scoped_stats, unscoped_stats)
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
        def record_supportability_metrics_timed(metrics)
          start_time = Time.now
          yield
          end_time = Time.now
          duration = (end_time - start_time).to_f
        ensure
          record_supportability_metrics(duration, metrics) do |value, metric|
            metric.record_data_point(value)
          end
        end

        # Helper for recording a straight value into the count
        def record_supportability_metrics_count(value, *metrics)
          record_supportability_metrics(value, *metrics) do |value, metric|
            metric.call_count = value
          end
        end

        # Helper method for recording supportability metrics consistently
        def record_supportability_metrics(value, *metrics)
          metrics.each do |metric|
              yield(value, get_stats_no_scope("Supportability/#{metric}"))
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

        # Harvest the timeslice data.  First recombine current statss
        # with any previously
        # unsent metrics, clear out stats cache, and return the current
        # stats.
        def harvest_timeslice_data(old_stats_hash, rules_engine=RulesEngine.new)
          poll harvest_samplers
          snapshot = reset_stats
          snapshot = apply_rules_to_metric_data(rules_engine, snapshot)
          snapshot.merge!(old_stats_hash)
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
      end
    end
  end
end
