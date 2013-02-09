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

        # This module was extracted from the harvest method and should
        # be refactored
        module Harvest
          # merge data from previous harvests into this stats engine -
          # takes into account the case where there are new stats for
          # that metric, and the case where there is no current data
          # for that metric
          def merge_data(metric_data_hash)
            # Normalize our input data, which is in a weird hash format where
            # keys are MetricSpec instances and values are either Stats
            # instances or MetricData instances. This should really be cleaned
            # up upstream of this call, but one step at a time.
            new_stats_hash = StatsHash.new
            metric_data_hash.each do |metric_spec, metric_data|
              new_stats = if metric_data.respond_to?(:stats)
                metric_data.stats
              else
                metric_data
              end
              new_stats_hash[metric_spec] = new_stats
            end

            with_stats_lock do
              @stats_hash.merge!(new_stats_hash)
            end
          end

          def reset_stats
            with_stats_lock do
              old = @stats_hash
              @stats_hash = StatsHash.new
              old
            end
          end

          private

          def coerce_to_metric_spec(metric_spec)
            if metric_spec.is_a?(NewRelic::MetricSpec)
              metric_spec
            else
              NewRelic::MetricSpec.new(metric_spec)
            end
          end

          # if the previous timeslice data has not been reported (due to an error of some sort)
          # then we need to merge this timeslice with the previously accumulated - but not sent
          # data
          def merge_old_data!(metric_spec, stats, old_data)
            metric_data = old_data[metric_spec]
            stats.merge!(metric_data.stats) unless metric_data.nil?
          end

          def add_data_to_send_unless_empty(data, stats, metric_spec, id)
            # don't bother collecting and reporting stats that have
            # zero-values for this timeslice. significant
            # performance boost and storage savings.
            return if stats.is_reset?
            data[metric_spec] = NewRelic::MetricData.new((id ? nil : metric_spec), stats, id)
          end

          def merge_stats(other_metric_data, metric_ids)
            timeslice_data = {}
            stats_hash_copy = reset_stats
            stats_hash_copy.each do |metric_spec, stats|
              metric_spec = coerce_to_metric_spec(metric_spec)
              raise "nil stats for #{metric_spec.name} (#{metric_spec.scope})" unless stats
              merge_old_data!(metric_spec, stats, other_metric_data)
              add_data_to_send_unless_empty(timeslice_data, stats, metric_spec, metric_ids[metric_spec])
            end
            timeslice_data
          end

        end
        include Harvest

        # Harvest the timeslice data.  First recombine current statss
        # with any previously
        # unsent metrics, clear out stats cache, and return the current
        # stats.
        # ---
        # Note: this is not synchronized.  There is still some risk in this and
        # we will revisit later to see if we can make this more robust without
        # sacrificing efficiency.
        # +++
        def harvest_timeslice_data(previous_timeslice_data, metric_ids,
                                   rules_engine=RulesEngine.new)
          poll harvest_samplers
          apply_rules_to_metric_data(rules_engine,
                              merge_stats(previous_timeslice_data, metric_ids))
        end

        def apply_rules_to_metric_data(rules_engine, stats_hash)
          renamed_stats = {}
          stats_hash.each do |spec, data|
            new_name = rules_engine.rename(spec.name)
            data.metric_spec = NewRelic::MetricSpec.new(new_name, spec.scope)
            if renamed_stats.has_key?(data.metric_spec)
              renamed_stats[data.metric_spec].stats.merge!(data.stats)
            else
              renamed_stats[data.metric_spec] = data
            end
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
