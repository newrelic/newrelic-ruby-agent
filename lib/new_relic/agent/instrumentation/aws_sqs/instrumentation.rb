# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module AwsSqs
    MESSAGING_LIBRARY = 'SQS'

    def send_message_with_new_relic(*args)
      segment = nil
      begin
        queue_name = get_queue_name(args[0])
        segment = NewRelic::Agent::Tracer.start_message_broker_segment(
          action: :produce,
          library: MESSAGING_LIBRARY,
          destination_type: :queue,
          destination_name: queue_name
        )
        add_aws_attributes(segment, queue_name, args[0])
      rescue => e
        NewRelic::Agent.logger.error('Error starting message broker segment in Aws::SQS::Client#send_message ', e)
      end
      NewRelic::Agent::Tracer.capture_segment_error(segment) do
        yield
      end
    ensure
      segment&.finish
    end

    def send_message_batch_with_new_relic(*args)
      segment = nil
      begin
        queue_name = get_queue_name(args[0])
        segment = NewRelic::Agent::Tracer.start_message_broker_segment(
          action: :produce,
          library: MESSAGING_LIBRARY,
          destination_type: :queue,
          destination_name: queue_name
        )
        add_aws_attributes(segment, queue_name, args[0])
      rescue => e
        NewRelic::Agent.logger.error('Error starting message broker segment in Aws::SQS::Client#send_message_batch ', e)
      end
      NewRelic::Agent::Tracer.capture_segment_error(segment) do
        yield
      end
    ensure
      segment&.finish
    end

    def receive_message_with_new_relic(*args)
      segment = nil
      begin
        queue_name = get_queue_name(args[0])
        segment = NewRelic::Agent::Tracer.start_message_broker_segment(
          action: :consume,
          library: MESSAGING_LIBRARY,
          destination_type: :queue,
          destination_name: queue_name
        )
        add_aws_attributes(segment, queue_name, args[0])
      rescue => e
        NewRelic::Agent.logger.error('Error starting message broker segment in Aws::SQS::Client#receive_message ', e)
      end
      NewRelic::Agent::Tracer.capture_segment_error(segment) do
        yield
      end
    ensure
      segment&.finish
    end

    def add_aws_attributes(segment, queue_name, params)
      segment&.add_agent_attribute('messaging.system', 'aws_sqs')
      segment&.add_agent_attribute('cloud.region', config&.region)
      segment&.add_agent_attribute('cloud.account.id', get_account_id(params))
      segment&.add_agent_attribute('messaging.destination.name', queue_name)
    end

    def get_queue_name(params)
      params[:queue_url].split('/').last
    end

    def get_account_id(params)
      params[:queue_url].split('/')[-2]
    end
  end
end
