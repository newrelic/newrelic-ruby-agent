# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'redis'
require 'new_relic/dependency_detection'
require 'new_relic/agent/instrumentation/redis'

# Primarily just tests allocations around argument formatting
class RedisTest < Performance::TestCase
  ITERATIONS = 500_000

  def test_no_args
    with_config(:'transaction_tracer.record_redis_arguments' => true) do
      command = ['lonely_command']
      measure(ITERATIONS) do
        NewRelic::Agent::Datastores::Redis.format_command(command)
      end
    end
  end

  def test_args
    with_config(:'transaction_tracer.record_redis_arguments' => true) do
      commands = %w[argumentative commands get called a bunch]
      measure(ITERATIONS) do
        NewRelic::Agent::Datastores::Redis.format_command(commands)
      end
    end
  end

  def test_long_args
    with_config(:'transaction_tracer.record_redis_arguments' => true) do
      commands = ['loooooong_command', 'a' * 100, 'b' * 100, 'c' * 100]
      measure(ITERATIONS) do
        NewRelic::Agent::Datastores::Redis.format_command(commands)
      end
    end
  end

  def test_pipelined
    with_config(:'transaction_tracer.record_redis_arguments' => true) do
      pipeline = [
        ['first', 'a' * 100, 'b' * 100, 'c' * 100],
        ['second', 'a' * 100, 'b' * 100, 'c' * 100]
      ]

      measure(ITERATIONS) do
        NewRelic::Agent::Datastores::Redis.format_pipeline_commands(pipeline)
      end
    end
  end
end
