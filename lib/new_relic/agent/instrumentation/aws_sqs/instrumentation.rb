# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module AwsSqs
    def send_message_with_new_relic(*args)
      segment = nil
      begin
        queue_name = get_queue_name(args[0])
        segment = NewRelic::Agent::Tracer.start_message_broker_segment(
          action: 'Produce',
          library: 'SQS',
          destination_type: 'Queue',
          destination_name: queue_name
        )
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
          action: 'Produce',
          library: 'SQS',
          destination_type: 'Queue',
          destination_name: queue_name
        )
      rescue => e
        NewRelic::Agent.logger.error('Error starting message broker segment in Aws::SQS::Client#send_message ', e)
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
          action: 'Consume',
          library: 'SQS',
          destination_type: 'Queue',
          destination_name: queue_name
        )
      rescue => e
        NewRelic::Agent.logger.error('Error starting message broker segment in Aws::SQS::Client#send_message ', e)
      end
      NewRelic::Agent::Tracer.capture_segment_error(segment) do
        yield
      end
    ensure
      segment&.finish
    end

    def get_queue_name(params)
      params[:queue_url].split('/').last
    end
  end
end
