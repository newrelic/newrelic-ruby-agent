# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

DependencyDetection.defer do
  named :mongo

  depends_on do
    if defined?(::Mongo) && defined?(::Mongo::Logging)
      true
    else
      if defined?(::Mongo)
        NewRelic::Agent.logger.info 'Mongo instrumentation requires Mongo::Logging'
      end

      false
    end
  end

  depends_on do
    require 'new_relic/agent/datastores/mongo'
    NewRelic::Agent::Datastores::Mongo.is_supported_version?
  end

  executes do
    NewRelic::Agent.logger.info 'Installing Mongo instrumentation'
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
      require 'new_relic/agent/datastores/mongo/metric_generator'
      require 'new_relic/agent/datastores/mongo/statement_formatter'

      def instrument_with_new_relic_trace(name, payload = {}, &block)
        metrics = NewRelic::Agent::Datastores::Mongo::MetricGenerator.generate_metrics_for(name, payload)

        trace_execution_scoped(metrics) do
          t0 = Time.now
          result = instrument_without_new_relic_trace(name, payload, &block)

          payload[:operation] = name
          statement = NewRelic::Agent::Datastores::Mongo::StatementFormatter.format(payload)
          if statement
            NewRelic::Agent.instance.transaction_sampler.notice_nosql_statement(statement, (Time.now - t0).to_f)
          end

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
      require 'new_relic/agent/datastores/mongo/metric_generator'
      require 'new_relic/agent/datastores/mongo/statement_formatter'

      def save_with_new_relic_trace(doc, opts = {}, &block)
        metrics = NewRelic::Agent::Datastores::Mongo::MetricGenerator.generate_metrics_for(:save, { :collection => self.name })

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
          statement = NewRelic::Agent::Datastores::Mongo::StatementFormatter.format(doc)
          if statement
            NewRelic::Agent.instance.transaction_sampler.notice_nosql_statement(statement, (Time.now - t0).to_f)
          end

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
      require 'new_relic/agent/datastores/mongo/metric_generator'
      require 'new_relic/agent/datastores/mongo/statement_formatter'

      def ensure_index_with_new_relic_trace(spec, opts = {}, &block)
        metrics = NewRelic::Agent::Datastores::Mongo::MetricGenerator.generate_metrics_for(:ensureIndex, { :collection => self.name })

        trace_execution_scoped(metrics) do
          t0 = Time.now

          transaction_state = NewRelic::Agent::TransactionState.get
          transaction_state.push_traced(false)

          begin
            result = ensure_index_without_new_relic_trace(spec, opts, &block)
          ensure
            transaction_state.pop_traced
          end

          spec = spec.is_a?(Array) ? Hash[spec] : spec.dup
          spec[:operation] = :ensureIndex

          statement = NewRelic::Agent::Datastores::Mongo::StatementFormatter.format(spec)
          if statement
            NewRelic::Agent.instance.transaction_sampler.notice_nosql_statement(statement, (Time.now - t0).to_f)
          end

          result
        end
      end

      alias_method :ensure_index_without_new_relic_trace, :ensure_index
      alias_method :ensure_index, :ensure_index_with_new_relic_trace
    end
  end
end
