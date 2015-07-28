# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/datastores/redis'
require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

class NewRelic::Agent::Datastores::RedisTest < Minitest::Test
  def test_format_command
    expected = "set \"foo\" \"bar\""

    with_config(:'transaction_tracer.record_redis_arguments' => true) do
      result = NewRelic::Agent::Datastores::Redis.format_command([:set, 'foo', 'bar'])
      assert_equal expected, result
    end
  end

  def test_format_command_truncates_long_arguments
    key = "namespace.other_namespace.different_namespace.why.would.you.do.this.key"
    expected_key = "namespace.other_namespace.dif...ace.why.would.you.do.this.key"

    expected = "set \"#{expected_key}\" \"redoctober\""

    with_config(:'transaction_tracer.record_redis_arguments' => true) do
      result = NewRelic::Agent::Datastores::Redis.format_command([:set, key, 'redoctober'])
      assert_equal expected, result
    end
  end

  def test_format_command_truncates_long_commands
    key = "key"
    command = [:set] + Array.new(NewRelic::Agent::Datastores::Redis::MAXIMUM_COMMAND_LENGTH, key)

    with_config(:'transaction_tracer.record_redis_arguments' => true) do
      result = NewRelic::Agent::Datastores::Redis.format_command(command)
      assert result.length <= NewRelic::Agent::Datastores::Redis::MAXIMUM_COMMAND_LENGTH
    end
  end

  def test_format_command_with_record_arguments_false
    with_config(:'transaction_tracer.record_redis_arguments' => false) do
      result = NewRelic::Agent::Datastores::Redis.format_command([:set, 'foo', 'bar'])
      assert_equal nil, result
    end
  end

  def test_format_command_in_pipeline
    expected = "set \"foo\" \"bar\""

    with_config(:'transaction_tracer.record_redis_arguments' => true) do
      result = NewRelic::Agent::Datastores::Redis.format_command([:set, 'foo', 'bar'])
      assert_equal expected, result
    end
  end

  def test_append_command_in_pipeline_with_record_arguments_false
    expected = "set ?"

    with_config(:'transaction_tracer.record_redis_arguments' => false) do
      result = ""
      NewRelic::Agent::Datastores::Redis.append_pipeline_command(result, [:set, 'foo', 'bar'])
      assert_equal expected, result
    end
  end

  def test_append_command_in_pipeline_with_record_arguments_and_no_args
    expected = "multi"

    with_config(:'transaction_tracer.record_redis_arguments' => true) do
      result = ""
      NewRelic::Agent::Datastores::Redis.append_pipeline_command(result, [:multi])
      assert_equal expected, result
    end
  end

  def test_append_command_in_pipeline_with_record_arguments_false_and_no_args
    expected = "multi"

    with_config(:'transaction_tracer.record_redis_arguments' => false) do
      result = ""
      NewRelic::Agent::Datastores::Redis.append_pipeline_command(result, [:multi])
      assert_equal expected, result
    end
  end

  def test_format_pipeline_commands_truncates_long_commands
    pipeline = NewRelic::Agent::Datastores::Redis::MAXIMUM_COMMAND_LENGTH.times.map do
      [:set, "0123456789"]
    end

    with_config(:'transaction_tracer.record_redis_arguments' => true) do
      result = NewRelic::Agent::Datastores::Redis.format_pipeline_commands(pipeline)
      assert NewRelic::Agent::Datastores::Redis::MAXIMUM_COMMAND_LENGTH, result.length
      assert result.end_with?("012345...")
    end
  end

  def test_format_command_with_non_string_argument
    expected = "set \"key\" true"

    with_config(:'transaction_tracer.record_redis_arguments' => true) do
      result = NewRelic::Agent::Datastores::Redis.format_command([:set, 'key', true])
      assert_equal expected, result
    end
  end

  if !NewRelic::LanguageSupport.rubinius? && RUBY_VERSION != "1.8.7"
    def test_format_command_handles_binary_strings
      binary_string = (0..255).to_a.pack("c*")
      expected = 'set "key" <binary data>'

      with_config(:'transaction_tracer.record_redis_arguments' => true) do
        result = NewRelic::Agent::Datastores::Redis.format_command([:set, 'key', binary_string])
        assert_equal expected, result
      end
    end

    def test_format_command_in_pipeline_handles_binary_strings
      binary_string = (0..255).to_a.pack("c*")
      expected = 'set "key" <binary data>'

      with_config(:'transaction_tracer.record_redis_arguments' => true) do
        result = NewRelic::Agent::Datastores::Redis.format_command([:set, 'key', binary_string])
        assert_equal expected, result
      end
    end
  end
end
