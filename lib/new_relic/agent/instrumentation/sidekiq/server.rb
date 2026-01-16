# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation::Sidekiq
  class Server
    include NewRelic::Agent::Instrumentation::ControllerInstrumentation
    include Sidekiq::ServerMiddleware if defined?(Sidekiq::ServerMiddleware)

    ATTRIBUTE_BASE_NAMESPACE = 'sidekiq.args'
    ATTRIBUTE_FILTER_TYPES = %i[include exclude].freeze
    ATTRIBUTE_JOB_NAMESPACE = :"job.#{ATTRIBUTE_BASE_NAMESPACE}"
    INSTRUMENTATION_NAME = 'SidekiqServer'

    # Client middleware has additional parameters, and our tests use the
    # middleware client-side to work inline.
    def call(worker, msg, queue, *_)
      NewRelic::Agent.record_instrumentation_invocation(INSTRUMENTATION_NAME)

      trace_args = if worker.respond_to?(:newrelic_trace_args)
        worker.newrelic_trace_args(msg, queue)
      else
        self.class.default_trace_args(msg)
      end
      trace_headers = msg.delete(NewRelic::NEWRELIC_KEY)

      execution_block = proc do
        NewRelic::Agent::Transaction.merge_untrusted_agent_attributes(
          NewRelic::Agent::AttributePreFiltering.pre_filter(msg['args'], self.class.nr_attribute_options),
          ATTRIBUTE_JOB_NAMESPACE,
          NewRelic::Agent::AttributeFilter::DST_NONE
        )

        if ::NewRelic::Agent.config[:'distributed_tracing.enabled'] && trace_headers&.any?
          ::NewRelic::Agent::DistributedTracing.accept_distributed_trace_headers(trace_headers, 'Other')
        end

        yield
      end

      if NewRelic::Agent.config[:'sidekiq.ignore_retry_errors']
        perform_action_with_newrelic_trace_without_error_reporting(trace_args, &execution_block)
      else
        perform_action_with_newrelic_trace(trace_args, &execution_block)
      end
    end

    private

    # Version of perform_action_with_newrelic_trace that doesn't report errors
    def perform_action_with_newrelic_trace_without_error_reporting(*args, &block)
      NewRelic::Agent.record_api_supportability_metric(:perform_action_with_newrelic_trace_without_error_reporting)
      state = NewRelic::Agent::Tracer.state
      request = newrelic_request(args)
      queue_start_time = detect_queue_start_time(request)

      skip_tracing = do_not_trace? || !state.is_execution_traced?

      if skip_tracing
        state.current_transaction&.ignore!
        NewRelic::Agent.disable_all_tracing { return yield }
      end

      trace_options = args.last.is_a?(Hash) ? args.last : NewRelic::EMPTY_HASH
      category = trace_options[:category] || :controller
      txn_options = create_transaction_options(trace_options, category, state, queue_start_time)

      begin
        finishable = NewRelic::Agent::Tracer.start_transaction_or_segment(
          name: txn_options[:transaction_name],
          category: category,
          options: txn_options
        )

        yield
      ensure
        finishable&.finish
      end
    end

    def self.default_trace_args(msg)
      {
        :name => 'perform',
        :class_name => msg['class'],
        :category => 'OtherTransaction/SidekiqJob'
      }
    end

    def self.nr_attribute_options
      @nr_attribute_options ||= begin
        ATTRIBUTE_FILTER_TYPES.each_with_object({}) do |type, opts|
          pattern =
            NewRelic::Agent::AttributePreFiltering.formulate_regexp_union(:"#{ATTRIBUTE_BASE_NAMESPACE}.#{type}")
          opts[type] = pattern if pattern
        end.merge(attribute_namespace: ATTRIBUTE_JOB_NAMESPACE)
      end
    end
  end
end
