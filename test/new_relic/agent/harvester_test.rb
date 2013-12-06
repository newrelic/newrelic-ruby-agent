# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/harvester'

module NewRelic
  module Agent
    class HarvesterTest < Test::Unit::TestCase

      attr_reader :harvester
      def setup
        @harvester = Harvester.new(nil)

        # Make sure we don't actually start things up
        NewRelic::Agent.stubs(:after_fork)
      end

      def test_marks_started_in_process
        pretend_started_in_another_process
        harvester.on_transaction

        assert harvester.started_in_current_process?
      end

      def test_skips_out_early_if_already_started
        harvester.mark_started
        ::Mutex.any_instance.expects(:synchronize).never
        harvester.on_transaction
      end

      def test_calls_to_restart
        pretend_started_in_another_process
        NewRelic::Agent.expects(:after_fork).once
        harvester.on_transaction
      end

      def test_calls_to_restart_only_once
        pretend_started_in_another_process
        NewRelic::Agent.expects(:after_fork).once

        threads = []
        100.times do
          threads << Thread.new do
            harvester.on_transaction
          end
        end

        threads.each do |thread|
          thread.join
        end
      end

      def pretend_started_in_another_process
        harvester.mark_started(Process.pid - 1)
      end
    end
  end
end
