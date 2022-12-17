# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'concurrent_ruby/instrumentation'
require_relative 'concurrent_ruby/chain'
require_relative 'concurrent_ruby/prepend'

DependencyDetection.defer do
  named :'concurrent_ruby'

  depends_on do
    defined?(Concurrent)
  end

  executes do
    NewRelic::Agent.logger.info('Installing concurrent-ruby instrumentation')

    if use_prepend?
      prepend_instrument(Concurrent::ThreadPoolExecutor, NewRelic::Agent::Instrumentation::ConcurrentRuby::Prepend)
      # prepend_instrument()
      # prepend_instrument()
      extra_prepend
    else
      chain_instrument NewRelic::Agent::Instrumentation::ConcurrentRuby::Chain
    end
  end
end

def extra_prepend
  # Concurrent::Promises::InternalStates::Rejected
  Concurrent::Promises.const_get(:'InternalStates')::Rejected.prepend(TestingStuff)
end

module TestingStuff
  def initialize(*args)
    NewRelic::Agent.notice_error(args.last)
    super
  end
end
