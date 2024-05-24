# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'dynamodb/instrumentation'
require_relative 'dynamodb/chain'
require_relative 'dynamodb/prepend'

DependencyDetection.defer do
  named :dynamodb

  depends_on do
    defined?(Aws::DynamoDB::Client)
  end

  executes do
    NewRelic::Agent.logger.info('Installing DynamoDB instrumentation')

    if use_prepend?
      prepend_instrument Aws::DynamoDB::Client, NewRelic::Agent::Instrumentation::DynamoDB::Prepend
    else
      chain_instrument NewRelic::Agent::Instrumentation::DynamoDB::Chain
    end
  end
end
