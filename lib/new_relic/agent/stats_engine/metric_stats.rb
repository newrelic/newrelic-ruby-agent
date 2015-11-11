# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/language_support'

module NewRelic
  module Agent
    # @api public
    class StatsEngine
      # Handles methods related to actual Metric collection
      # @api public
      module MetricStats
        SCOPE_PLACEHOLDER = '__SCOPE__'.freeze

        # Update the unscoped metrics given in metric_names.
        # metric_names may be either a single name, or an array of names.
        #
        # This is an internal method, subject to change at any time. Client apps
        # and gems should use the public API (NewRelic::Agent.record_metric)
        # instead.
        #
        # There are four ways to use this method:
        #
        # 1. With a numeric value, it will update the Stats objects associated
        #    with the given metrics by calling record_data_point(value, aux).
        #    aux will be treated in this case as the exclusive time associated
        #    with the call being recorded.
        #
        # 2. With a value of :apdex_s, :apdex_t, or :apdex_f, it will treat the
        #    associated stats as an Apdex metric, updating it to reflect the
        #    occurrence of a transaction falling into the given category.
        #    The aux value in this case should be the apdex threshold used in
        #    bucketing the request.
        #
        # 3. If a block is given, value and aux will be ignored, and instead the
        #    Stats object associated with each named unscoped metric will be
        #    yielded to the block for customized update logic.
        #
        # 4. If value is a Stats instance, it will be merged into the Stats
        #    associated with each named unscoped metric.
        #
        # If this method is called during a transaction, the metrics will be
        # attached to the Transaction, and not merged into the global set until
        # the end of the transaction.
        #
        # Otherwise, the metrics will be recorded directly into the global set
        # of metrics, under a lock.
        #
        # @api private
        #
        def tl_record_unscoped_metrics(metric_names, value=nil, aux=nil, &blk)
          state = NewRelic::Agent::TransactionState.tl_get
          record_unscoped_metrics(state, metric_names, value, aux, &blk)
        end

        def record_unscoped_metrics(state, metric_names, value=nil, aux=nil, &blk)
          txn = state.current_transaction
          if txn
            txn.metrics.record_unscoped(metric_names, value, aux, &blk)
          else
            specs = coerce_to_metric_spec_array(metric_names, nil)
            with_stats_lock do
              @stats_hash.record(specs, value, aux, &blk)
            end
          end
        end

        # Like tl_record_unscoped_metrics, but records a scoped metric as well.
        #
        # This is an internal method, subject to change at any time. Client apps
        # and gems should use the public API (NewRelic::Agent.record_metric)
        # instead.
        #
        # The given scoped_metric will be recoded as both a scoped *and* an
        # unscoped metric. The summary_metrics will be recorded as unscoped
        # metrics only.
        #
        # If called during a transaction, all metrics will be attached to the
        # Transaction, and not merged into the global set of metrics until the
        # end of the transaction.
        #
        # If called outside of a transaction, only the *unscoped* metrics will
        # be recorded, directly into the global set of metrics (under a lock).
        #
        # @api private
        #
        def tl_record_scoped_and_unscoped_metrics(scoped_metric, summary_metrics=nil, value=nil, aux=nil, &blk)
          state = NewRelic::Agent::TransactionState.tl_get
          record_scoped_and_unscoped_metrics(state, scoped_metric, summary_metrics, value, aux, &blk)
        end

        def record_scoped_and_unscoped_metrics(state, scoped_metric, summary_metrics=nil, value=nil, aux=nil, &blk)
          txn = state.current_transaction
          if txn
            txn.metrics.record_scoped_and_unscoped(scoped_metric, value, aux, &blk)
            if summary_metrics
              txn.metrics.record_unscoped(summary_metrics, value, aux, &blk)
            end
          else
            specs = coerce_to_metric_spec_array(scoped_metric, nil)
            if summary_metrics
              specs.concat(coerce_to_metric_spec_array(summary_metrics, nil))
            end
            with_stats_lock do
              @stats_hash.record(specs, value, aux, &blk)
            end
          end
        end

        # This method is deprecated and not thread safe, and should not be used
        # by any new client code.
        #
        # Lookup the Stats object for a given unscoped metric, returning a new
        # Stats object if one did not exist previously.
        #
        # @api public
        # @deprecated Use {::NewRelic::Agent.record_metric} instead.
        #
        def get_stats_no_scope(metric_name)
          get_stats(metric_name, false)
        end

        # This method is deprecated and not thread safe, and should not be used
        # by any new client code. Use NewRelic::Agent.record_metric instead.
        #
        # If scoped_metric_only is true, only a scoped metric is created (used
        # by rendering metrics which by definition are per controller only)
        # Leaving second, unused parameter for compatibility
        #
        # @api public
        # @deprecated Use {::NewRelic::Agent.record_metric} instead.
        #
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

        # Helper for recording a straight value into the count
        def tl_record_supportability_metric_count(metric, value)
          real_name = "Supportability/#{metric}"
          tl_record_unscoped_metrics(real_name) do |stat|
            stat.call_count = value
          end
        end

        def reset!
          with_stats_lock do
            old = @stats_hash
            @stats_hash = StatsHash.new
            old
          end
        end

        # Renamed to reset!, here for backwards compatibility with 3rd-party
        # gems (though this really isn't part of the public API).
        # @deprecated
        def reset_stats; reset!; end

        # merge data from previous harvests into this stats engine
        def merge!(other_stats_hash)
          with_stats_lock do
            @stats_hash.merge!(other_stats_hash)
            @stats_hash
          end
        end

        def merge_transaction_metrics!(txn_metrics, scope)
          with_stats_lock do
            @stats_hash.merge_transaction_metrics!(txn_metrics, scope)
          end
        end

        def harvest!
          now = Time.now
          snapshot = reset!
          snapshot = apply_rules_to_metric_data(@metric_rules, snapshot)
          snapshot.harvested_at = now
          snapshot
        end

        def apply_rules_to_metric_data(rules_engine, stats_hash)
          renamed_stats = NewRelic::Agent::StatsHash.new(stats_hash.started_at)
          stats_hash.each do |spec, stats|
            new_name = rules_engine.rename(spec.name)
            unless new_name.nil?
              new_spec = NewRelic::MetricSpec.new(new_name, spec.scope)
              renamed_stats[new_spec].merge!(stats)
            end
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
          reset!
          NewRelic::Agent::BusyCalculator.reset
        end

        # For use by test code only.
        def to_h
          with_stats_lock { @stats_hash.to_h }
        end
      end
    end
  end
end
