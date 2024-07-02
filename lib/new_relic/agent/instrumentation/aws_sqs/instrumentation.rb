# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module AwsSqs
    MESSAGING_LIBRARY = 'SQS'

    def send_message_with_new_relic(*args)
      with_tracing(:produce, args) do
        yield
      end
    end

    def send_message_batch_with_new_relic(*args)
      with_tracing(:produce, args) do
        yield
      end
    end

    def receive_message_with_new_relic(*args)
      with_tracing(:consume, args) do
        yield
      end
    end

    def with_tracing(action, params)
      segment = nil
      begin
        info = get_url_info(params[0])
        segment = NewRelic::Agent::Tracer.start_message_broker_segment(
          action: action,
          library: MESSAGING_LIBRARY,
          destination_type: :queue,
          destination_name: info[:queue_name]
        )
        add_aws_attributes(segment, info)
      rescue => e
        NewRelic::Agent.logger.error('Error starting message broker segment in Aws::SQS::Client', e)
      end
      NewRelic::Agent::Tracer.capture_segment_error(segment) do
        yield
      end
    ensure
      segment&.finish
    end

    private

    def add_aws_attributes(segment, info)
      return unless segment

      segment.add_agent_attribute('messaging.system', 'aws_sqs')
      segment.add_agent_attribute('cloud.region', config&.region)
      segment.add_agent_attribute('cloud.account.id', info[:account_id])
      segment.add_agent_attribute('messaging.destination.name', info[:queue_name])
    end

    def get_url_info(params)
      split = params[:queue_url].split('/')
      {
        queue_name: split.last,
        account_id: split[-2]
      }
    end
  end
end
