# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    class Transaction
      # Centralized module for making sampling decisions and setting priority.
      # This consolidates logic previously duplicated across Transaction,
      # DistributedTracing, and TraceContext.
      module SamplingDecision
        extend self

        # Determines sampling decision and priority for a root transaction
        # (i.e., a transaction that originates in the service running the agent).
        # Note: Priority is always calculated even when distributed tracing is disabled,
        # as it's an intrinsic transaction attribute.
        #
        # @param transaction [Transaction] the transaction to sample
        # @return [Hash] with keys :sampled (Boolean) and :priority (Float)
        #
        # @api private
        def determine_root_sampling(transaction)
          trace_id = transaction.trace_id
          config_value = NewRelic::Agent.config[:'distributed_tracing.sampler.root']

          case config_value
          when 'default', 'adaptive'
            sampled = NewRelic::Agent.instance.adaptive_sampler.sampled?
            priority = adaptive_priority(sampled)
          when 'always_on'
            sampled = true
            priority = 2.0
          when 'always_off'
            sampled = false
            priority = 0
          when 'trace_id_ratio_based'
            ratio = NewRelic::Agent.config[:'distributed_tracing.sampler.root.trace_id_ratio_based.ratio']
            if valid_ratio?(ratio)
              sampled = calculate_trace_id_ratio_sampled(ratio, trace_id)
              priority = sampled ? 2.0 : 0
            else
              # Fall back to adaptive if ratio is invalid or nil
              sampled = NewRelic::Agent.instance.adaptive_sampler.sampled?
              priority = adaptive_priority(sampled)
            end
          else
            # Unknown config value, fall back to adaptive
            sampled = NewRelic::Agent.instance.adaptive_sampler.sampled?
            priority = adaptive_priority(sampled)
          end

          {sampled: sampled, priority: priority}
        end

        # Determines sampling decision and priority for a distributed trace
        # based on remote parent's sampling information.
        #
        # @param config_key [Symbol] the config key to check (e.g., 'distributed_tracing.sampler.remote_parent_sampled')
        # @param ratio_key [Symbol] the related ratio config
        #   (e.g., 'distributed_tracing.sampler.remote_parent_sampled.trace_id_ratio_based.ratio')
        #   to use when the config key's value is 'trace_id_ratio_based'
        # @param trace_id [String] the trace ID
        # @param payload [Object] the payload containing sampled/priority from parent
        # @return [Hash] with keys :sampled (Boolean) and :priority (Float)
        #
        # @api private
        def determine_remote_sampling(config_key, ratio_key, trace_id, payload)
          config_value = NewRelic::Agent.config[config_key]

          case config_value
          when 'default', 'adaptive'
            use_payload_sampling(payload)
          when 'always_on'
            {sampled: true, priority: 2.0}
          when 'always_off'
            {sampled: false, priority: 0}
          when 'trace_id_ratio_based'
            ratio = NewRelic::Agent.config[ratio_key]
            if valid_ratio?(ratio)
              sampled = calculate_trace_id_ratio_sampled(ratio, trace_id)
              {sampled: sampled, priority: sampled ? 2.0 : 0}
            else
              # Fall back to payload if ratio is invalid or nil
              use_payload_sampling(payload)
            end
          else
            # Unknown config value, fall back to payload
            use_payload_sampling(payload)
          end
        end

        # Extracts sampling decision and priority from payload.
        #
        # @param payload [Object] the payload containing sampled/priority
        # @return [Hash] with keys :sampled (Boolean/nil) and :priority (Float/nil)
        #
        # @api private
        def use_payload_sampling(payload)
          result = {}
          unless payload.sampled.nil?
            result[:sampled] = payload.sampled
            result[:priority] = payload.priority if payload.priority
          end
          result
        end

        # Calculates whether a trace should be sampled based on a Trace ID ratio.
        #
        # @param ratio [Float] the sampling ratio (0.0 to 1.0)
        # @param trace_id [String] the trace ID to hash
        # @return [Boolean] true if sampled
        #
        # @api private
        def calculate_trace_id_ratio_sampled(ratio, trace_id)
          return true if ratio == 1.0

          upper_bound = (ratio * (2**64 - 1)).ceil
          trace_id[8, 8].unpack1('Q>') < upper_bound
        end

        # Validates that the ratio is a Float in the range [0.0, 1.0].
        #
        # @param ratio [Object] the value to validate
        # @return [Boolean] true if valid
        #
        # @api private
        def valid_ratio?(ratio)
          ratio.is_a?(Float) && (0.0..1.0).cover?(ratio)
        end

        # Calculates adaptive priority based on sampled status.
        #
        # @param sampled [Boolean] whether the transaction is sampled
        # @return [Float] priority value
        #
        # @api private
        def adaptive_priority(sampled)
          (sampled ? rand + 1.0 : rand).round(NewRelic::PRIORITY_PRECISION)
        end
      end
    end
  end
end
