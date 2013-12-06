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
    instrument_mongo_logging
    instrument_save
    instrument_ensure_index
  end

  def instrument_mongo_logging
    ::Mongo::Logging.class_eval do
      include NewRelic::Agent::MethodTracer
      require 'new_relic/agent/datastores/mongo/mongo_metric_translator'

      def instrument_with_new_relic_trace(name, payload = {}, &block)
        metrics = NewRelic::Agent::Datastores::Mongo::MetricTranslator.metrics_for(name, payload)

        trace_execution_scoped(metrics) do
          t0 = Time.now
          result = instrument_without_new_relic_trace(name, payload, &block)
          payload[:operation] = name
          NewRelic::Agent.instance.transaction_sampler.notice_nosql_query(payload, (Time.now - t0).to_f)
          result
        end
      end

      ::Mongo::Collection.class_eval { include Mongo::Logging; }
      ::Mongo::Connection.class_eval { include Mongo::Logging; }
      ::Mongo::Cursor.class_eval { include Mongo::Logging; }

      alias_method :instrument_without_new_relic_trace, :instrument
      alias_method :instrument, :instrument_with_new_relic_trace
    end
  end

  def instrument_save
    ::Mongo::Collection.class_eval do
      include NewRelic::Agent::MethodTracer
      require 'new_relic/agent/datastores/mongo/mongo_metric_translator'

      def save_with_new_relic_trace(doc, opts = {}, &block)
        metrics = NewRelic::Agent::Datastores::Mongo::MetricTranslator.metrics_for(:save, { :collection => self.name })

        trace_execution_scoped(metrics) do
          t0 = Time.now

          transaction_state = NewRelic::Agent::TransactionState.get
          transaction_state.push_traced(false)

          begin
            result = save_without_new_relic_trace(doc, opts, &block)
          ensure
            transaction_state.pop_traced
          end

          doc[:operation] = :save
          NewRelic::Agent.instance.transaction_sampler.notice_nosql_query(doc, (Time.now - t0).to_f)
          result
        end
      end

      alias_method :save_without_new_relic_trace, :save
      alias_method :save, :save_with_new_relic_trace
    end
  end

  def instrument_ensure_index
    ::Mongo::Collection.class_eval do
      include NewRelic::Agent::MethodTracer
      require 'new_relic/agent/datastores/mongo/mongo_metric_translator'

      def ensure_index_with_new_relic_trace(spec, opts = {}, &block)
        metrics = NewRelic::Agent::Datastores::Mongo::MetricTranslator.metrics_for(:ensureIndex, { :collection => self.name })

        trace_execution_scoped(metrics) do
          t0 = Time.now

          transaction_state = NewRelic::Agent::TransactionState.get
          transaction_state.push_traced(false)

          begin
            result = save_without_new_relic_trace(spec, opts, &block)
          ensure
            transaction_state.pop_traced
          end

          spec[:operation] = :ensureIndex
          NewRelic::Agent.instance.transaction_sampler.notice_nosql_query(spec, (Time.now - t0).to_f)
          result
        end
      end

      alias_method :ensure_index_without_new_relic_trace, :ensure_index
      alias_method :ensure_index, :ensure_index_with_new_relic_trace
    end
  end
end
