# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'aws_sdk_firehose/instrumentation'
require_relative 'aws_sdk_firehose/chain'
require_relative 'aws_sdk_firehose/prepend'

DependencyDetection.defer do
  named :aws_sdk_firehose

  depends_on do
    defined?(Aws::Firehose::Client)
  end
  executes do
    if use_prepend?
      prepend_instrument Aws::Firehose::Client, NewRelic::Agent::Instrumentation::Firehose::Prepend
    else
      chain_instrument NewRelic::Agent::Instrumentation::Firehose::Chain
    end
  end
end
