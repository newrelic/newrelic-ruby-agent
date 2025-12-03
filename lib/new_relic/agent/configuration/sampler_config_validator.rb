# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module Configuration
      # Handles validation for the `distributed_tracing.sampler.*` configs
      # Focuses on validating the trace id ratio based ratios
      module SamplerConfigValidator
        @sampler_strategy_warnings = {}

        class << self
          def validate_sampling_ratio(ratio)
            return nil if ratio.nil?
            return nil unless valid_ratio?(ratio)

            ratio
          end

          def validate_sampler_strategy_with_ratio(strategy_key, ratio_key)
            proc do |strategy|
              next strategy unless strategy == 'trace_id_ratio_based'

              ratio = NewRelic::Agent.config[ratio_key]

              next strategy if valid_ratio?(ratio)

              unless @sampler_strategy_warnings[strategy_key]
                NewRelic::Agent.logger.warn(
                  "Invalid or missing ratio for #{ratio_key} (value: #{ratio.inspect}). " \
                  "Falling back to 'adaptive' for #{strategy_key}."
                )

                @sampler_strategy_warnings[strategy_key] = true
              end

              'adaptive'
            end
          end

          def valid_ratio?(ratio)
            ratio.is_a?(Float) && (0.0..1.0).cover?(ratio)
          end

          # used for testing
          def reset_warnings!
            @sampler_strategy_warnings = {}
          end
        end
      end
    end
  end
end
