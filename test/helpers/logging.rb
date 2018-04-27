# frozen_string_literal: true

# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

def with_verbose_logging
  orig_logger = NewRelic::Agent.logger
  $stderr.puts '', '---', ''
  new_logger = NewRelic::Agent::AgentLogger.new('', Logger.new($stderr) )
  NewRelic::Agent.logger = new_logger

  with_config(:log_level => 'debug') do
    yield
  end
ensure
  NewRelic::Agent.logger = orig_logger
end

# Need to be a bit sloppy when testing against the logging--let everything
# through, but check we (at least) get our particular message we care about
def expects_logging(level, *with_params)
  ::NewRelic::Agent.logger.stubs(level)
  ::NewRelic::Agent.logger.expects(level).with(*with_params).once
end

def expects_no_logging(level)
  ::NewRelic::Agent.logger.expects(level).never
end

# Sometimes need to test cases where we muddle with the global logger
# If so, use this method to ensure it gets restored after we're done
def without_logger
  logger = ::NewRelic::Agent.logger
  ::NewRelic::Agent.logger = nil
  yield
ensure
  ::NewRelic::Agent.logger = logger
end
