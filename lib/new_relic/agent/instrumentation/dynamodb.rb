# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'dynamodb/instrumentation'
require_relative 'dynamodb/chain'
require_relative 'dynamodb/prepend'

DependencyDetection.defer do
  named :dynamodb

  depends_on do
    # The class that needs to be defined to prepend/chain onto. This can be used
    # to determine whether the library is installed.
    defined?(Aws::DynamoDB::Client)
    # Add any additional requirements to verify whether this instrumentation
    # should be installed
  end

  executes do
    NewRelic::Agent.logger.info('Installing dynamodb instrumentation')

    if use_prepend?
      prepend_instrument Aws::DynamoDB::Client, NewRelic::Agent::Instrumentation::Dynamodb::Prepend
    else
      chain_instrument NewRelic::Agent::Instrumentation::Dynamodb::Chain
    end
  end
end
