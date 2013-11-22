# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

DependencyDetection.defer do
  named :mongo

  depends_on do
    return false unless defined? ::Mongo

    unless defined? ::Mongo::Logging
      NewRelic::Agent.logger.debug 'Mongo instrumentation requires Mongo::Logging'
      false
    else
      true
    end
  end

  executes do
    NewRelic::Agent.logger.debug 'Installing Mongo instrumentation'
    install_mongo_instrumentation
  end

  def install_mongo_instrumentation
    ::Mongo::Logging.class_eval do
      include NewRelic::Agent::MethodTracer
      require 'new_relic/agent/datastores/mongo/mongo_metric_translator'

      def instrument_with_newrelic_trace(name, payload = {}, &block)
        metrics = NewRelic::Agent::MongoMetricTranslator.metrics_for(name, payload)

        trace_execution_scoped(metrics) do
          t0 = Time.now
          result = instrument_without_newrelic_trace(name, payload, &block)
          NewRelic::Agent.instance.transaction_sampler.notice_sql(payload.inspect, nil, (Time.now - t0).to_f)
          result
        end
      end

      ::Mongo::Collection.class_eval { include Mongo::Logging; }
      ::Mongo::Connection.class_eval { include Mongo::Logging; }
      ::Mongo::Cursor.class_eval { include Mongo::Logging; }

      alias_method :instrument_without_newrelic_trace, :instrument
      alias_method :instrument, :instrument_with_newrelic_trace
    end
  end
end
