# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../test_helper'
require 'new_relic/agent/fork_hook'

class NewRelic::Agent::ForkHookTest < Minitest::Test
  if NewRelic::LanguageSupport.can_fork? && Process.respond_to?(:_fork)
    def setup
      NewRelic::Agent.agent.drop_buffered_data
      NewRelic::Agent::ForkHook.install
    end

    def test_install_prepends_once
      assert NewRelic::Agent::ForkHook.install
      assert_equal 1, Process.singleton_class.ancestors.count(NewRelic::Agent::ForkHook)
    end

    def test_child_drops_data_inherited_from_parent
      record_log('parent log')
      NewRelic::Agent.record_custom_event('ForkHookTest', {})
      NewRelic::Agent.record_metric('Custom/ForkHookTest/parent', 1)

      child_logs, custom_event_count, metric_names = in_forked_child do
        [log_messages,
          NewRelic::Agent.agent.custom_event_aggregator.harvest![1].size,
          NewRelic::Agent.agent.stats_engine.to_h.keys.map(&:name)]
      end

      assert_empty child_logs
      assert_equal 0, custom_event_count
      refute_includes metric_names, 'Custom/ForkHookTest/parent'
      refute_includes metric_names, 'Supportability/API/drop_buffered_data'
    end

    def test_child_keeps_log_events_it_records_after_fork
      record_log('parent log')

      child_messages = in_forked_child do
        record_log('child log')
        log_messages
      end

      assert_equal ['child log'], child_messages
    end

    def test_parent_keeps_its_buffered_log_events
      record_log('parent log')
      in_forked_child { nil }

      assert_equal ['parent log'], log_messages
    end

    def test_child_leaves_after_fork_work_for_later
      assert(in_forked_child { NewRelic::Agent.agent.instance_variable_get(:@harvester).needs_restart? })
    end

    def test_child_continues_when_dropping_data_raises
      NewRelic::Agent.agent.stubs(:drop_buffered_data).raises(StandardError, 'boom')

      assert_equal :alive, in_forked_child { :alive }
    end

    def test_child_continues_when_forked_from_a_signal_handler
      read, write = IO.pipe
      child = nil
      previous = trap('USR2') do
        child = Process.fork do
          read.close
          write.write('alive')
          write.close
          exit!(0)
        end
      end
      Process.kill('USR2', Process.pid)
      sleep(0.01) until child
      write.close
      result = read.read
      Process.wait(child)

      assert_equal 'alive', result
    ensure
      trap('USR2', previous || 'DEFAULT')
    end

    private

    def in_forked_child
      read, write = IO.pipe
      pid = Process.fork do
        read.close
        Marshal.dump(yield, write)
      rescue StandardError => e
        Marshal.dump(e, write)
      ensure
        write.close
        exit!(0)
      end
      write.close
      result = Marshal.load(read.read)
      read.close
      Process.wait(pid)
      raise result if result.is_a?(StandardError)

      result
    end

    def record_log(message)
      NewRelic::Agent.agent.log_event_aggregator.record(message, 'INFO')
    end

    def log_messages
      NewRelic::Agent.agent.log_event_aggregator.harvest![1].map { |item| item.last['message'] }
    end
  end
end
