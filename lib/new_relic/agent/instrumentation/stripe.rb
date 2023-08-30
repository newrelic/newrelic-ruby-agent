# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'new_relic/agent/instrumentation/stripe_subscriber'

DependencyDetection.defer do
  named :stripe

  depends_on do
    NewRelic::Agent.config[:'instrumentation.stripe'] == 'enabled'
  end

  depends_on do
    defined?(Stripe) &&
      Gem::Version.new(Stripe::VERSION) >= Gem::Version.new('5.15.0') # Stripe subscribers added 5.15.0
  end

  executes do
    NewRelic::Agent.logger.info('Installing Stripe instrumentation')
  end

  executes do
    Stripe::Instrumentation.subscribe(:request_begin) { |event| NewRelic::Agent::Instrumentation::StripeSubscriber.new.start_segment(event) }
    Stripe::Instrumentation.subscribe(:request_end) { |event| NewRelic::Agent::Instrumentation::StripeSubscriber.new.finish_segment(event) }
  end
end
