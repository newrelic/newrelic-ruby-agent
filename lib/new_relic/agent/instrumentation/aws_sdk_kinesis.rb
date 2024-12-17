# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'aws_sdk_kinesis/instrumentation'
require_relative 'aws_sdk_kinesis/chain'
require_relative 'aws_sdk_kinesis/prepend'

DependencyDetection.defer do
  named :aws_sdk_kinesis

  depends_on do
    defined?(Aws::Kinesis::Client)
  end
  executes do
    if use_prepend?
      prepend_instrument Aws::Kinesis::Client, NewRelic::Agent::Instrumentation::Kinesis::Prepend
    else
      chain_instrument NewRelic::Agent::Instrumentation::Kinesis::Chain
    end
  end
end
