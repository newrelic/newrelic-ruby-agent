# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module PrependSupportability
      def self.record_metrics_for *classes
        classes.each do |klass|
          count = klass.send(:ancestors).index(klass)
          ::NewRelic::Agent.record_metric("Supportability/PrependedModules/#{klass}", count) if count > 0
        end
      end
    end
  end
end
