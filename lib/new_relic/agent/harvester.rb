# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class Harvester
      attr_accessor :starting_pid

      def initialize(events)
        @starting_pid = Process.pid
        @lock = Mutex.new

        if events
          events.subscribe(:start_transaction, &method(:on_transaction))
        end
      end

      def mark_started(pid = Process.pid)
        @starting_pid = pid
      end

      def started_in_current_process?(pid = Process.pid)
        @starting_pid == pid
      end

      def on_transaction(*_)
        return if started_in_current_process?

        needs_thread_start = false
        @lock.synchronize do
          needs_thread_start = !started_in_current_process?
          mark_started
        end

        if needs_thread_start
          # Daemonize reports thread as still alive when it isn't... whack!
          NewRelic::Agent.instance.instance_variable_set(:@worker_thread, nil)
          NewRelic::Agent.after_fork(:force_reconnect => true)
        end
      end

    end
  end
end
