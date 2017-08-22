module NewRelic
  module Agent
    module PrependSupportability
      def self.record_metrics_for *classes
        classes.each do |klass|
          count = klass.send(:ancestors).index(klass)
          ::NewRelic::Agent.record_metric("Supportability/PrependedModules/#{klass}", count)
        end
      end
    end
  end
end