# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

DependencyDetection.defer do
  named :mongo

  depends_on do
    defined?(::Mongo)
  end

  depends_on do
    require 'new_relic/agent/datastores/mongo'
    if NewRelic::Agent::Datastores::Mongo.is_unsupported_2x?
      NewRelic::Agent.logger.log_once(:info, :mongo2, 'Detected unsupported Mongo 2, upgrade your Mongo Driver to 2.1 or newer for instrumentation')
    end
    NewRelic::Agent::Datastores::Mongo.is_supported_version?
  end

  executes do
    NewRelic::Agent.logger.info 'Installing Mongo instrumentation'
    if NewRelic::Agent::Datastores::Mongo.is_monitoring_enabled?
      install_mongo_command_subscriber
    else
      install_mongo_instrumentation
    end
  end

  def install_mongo_command_subscriber
    require 'new_relic/agent/instrumentation/mongodb_command_subscriber'
    Mongo::Monitoring::Global.subscribe(
      Mongo::Monitoring::COMMAND,
      NewRelic::Agent::Instrumentation::MongodbCommandSubscriber.new
    )
  end

  def install_mongo_instrumentation
    require 'new_relic/agent/datastores/mongo/metric_translator'
    require 'new_relic/agent/datastores/mongo/statement_formatter'

    hook_instrument_methods
    instrument_save
    instrument_ensure_index
  end

  def hook_instrument_methods
    hook_instrument_method(::Mongo::Collection)
    hook_instrument_method(::Mongo::Connection)
    hook_instrument_method(::Mongo::Cursor)
    hook_instrument_method(::Mongo::CollectionWriter) if defined?(::Mongo::CollectionWriter)
  end

  def hook_instrument_method(target_class)
    target_class.class_eval do
      include NewRelic::Agent::MethodTracer

      # It's key that this method eats all exceptions, as it rests between the
      # Mongo operation the user called and us returning them the data. Be safe!
      def new_relic_notice_statement(t0, payload, name)
        statement = NewRelic::Agent::Datastores::Mongo::StatementFormatter.format(payload, name)
        if statement
          NewRelic::Agent.instance.transaction_sampler.notice_nosql_statement(statement, (Time.now - t0).to_f)
        end
      rescue => e
        NewRelic::Agent.logger.debug("Exception during Mongo statement gathering", e)
      end

      def new_relic_generate_metrics(operation, payload = nil)
        payload ||= { :collection => self.name, :database => self.db.name }
        NewRelic::Agent::Datastores::Mongo::MetricTranslator.metrics_for(operation, payload)
      end

      def instrument_with_new_relic_trace(name, payload = {}, &block)
        metrics = new_relic_generate_metrics(name, payload)

        trace_execution_scoped(metrics) do
          t0 = Time.now

          result = NewRelic::Agent.disable_all_tracing do
            instrument_without_new_relic_trace(name, payload, &block)
          end

          new_relic_notice_statement(t0, payload, name)
          result
        end
      end

      alias_method :instrument_without_new_relic_trace, :instrument
      alias_method :instrument, :instrument_with_new_relic_trace
    end
  end

  def instrument_save
    ::Mongo::Collection.class_eval do
      def save_with_new_relic_trace(doc, opts = {}, &block)
        metrics = new_relic_generate_metrics(:save)
        trace_execution_scoped(metrics) do
          t0 = Time.now

          result = NewRelic::Agent.disable_all_tracing do
            save_without_new_relic_trace(doc, opts, &block)
          end

          new_relic_notice_statement(t0, doc, :save)
          result
        end
      end

      alias_method :save_without_new_relic_trace, :save
      alias_method :save, :save_with_new_relic_trace
    end
  end

  def instrument_ensure_index
    ::Mongo::Collection.class_eval do
      def ensure_index_with_new_relic_trace(spec, opts = {}, &block)
        metrics = new_relic_generate_metrics(:ensureIndex)
        trace_execution_scoped(metrics) do
          t0 = Time.now

          result = NewRelic::Agent.disable_all_tracing do
            ensure_index_without_new_relic_trace(spec, opts, &block)
          end

          spec = case spec
                 when Array
                   Hash[spec]
                 when String, Symbol
                   { spec => 1 }
                 else
                   spec.dup
                 end

          new_relic_notice_statement(t0, spec, :ensureIndex)
          result
        end
      end

      alias_method :ensure_index_without_new_relic_trace, :ensure_index
      alias_method :ensure_index, :ensure_index_with_new_relic_trace
    end
  end
end
