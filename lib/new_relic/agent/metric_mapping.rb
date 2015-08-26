# -*- ruby -*-
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module MetricMapping

      SPEC_MAPPINGS = {}

      def self.included base
        base.extend ClassMethods
      end

      module ClassMethods
        def map_metric(metric_name, to_add={})
          to_add.values.each(&:freeze)

          mappings = SPEC_MAPPINGS.fetch(metric_name, {})
          mappings.merge!(to_add)

          SPEC_MAPPINGS[metric_name] = mappings
        end
      end

      def append_mapped_metrics(txn_metrics, sample)
        if txn_metrics
          SPEC_MAPPINGS.each do |(name, extracted_values)|
            if txn_metrics.has_key?(name)
              stat = txn_metrics[name]
              extracted_values.each do |value_name, key_name|
                sample[key_name] = stat.send(value_name)
              end
            end
          end
        end
      end
    end
  end
end
