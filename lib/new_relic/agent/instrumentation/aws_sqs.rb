# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'aws_sqs/instrumentation'
require_relative 'aws_sqs/chain'
require_relative 'aws_sqs/prepend'

DependencyDetection.defer do
  named :aws_sqs

  depends_on do
    defined?(::Aws::SQS::Client)
  end

  executes do
    ::NewRelic::Agent.logger.info('Installing aws-sdk-sqs instrumentation')

    if use_prepend?
      prepend_instrument ::Aws::SQS::Client, NewRelic::Agent::Instrumentation::AwsSqs::Prepend
    else
      chain_instrument NewRelic::Agent::Instrumentation::AwsSqs::Chain
    end
  end
end
