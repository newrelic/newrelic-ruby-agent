# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

DependencyDetection.defer do
  named :aws_sdk_lambda

  depends_on do
    defined?(Aws::Lambda::Client)
  end

  executes do
    require_relative 'aws_sdk_lambda/instrumentation'

    if use_prepend?
      require_relative 'aws_sdk_lambda/prepend'
      prepend_instrument Aws::Lambda::Client, NewRelic::Agent::Instrumentation::AwsSdkLambda::Prepend
    else
      require_relative 'aws_sdk_lambda/chain'
      chain_instrument NewRelic::Agent::Instrumentation::AwsSdkLambda::Chain
    end
  end
end
