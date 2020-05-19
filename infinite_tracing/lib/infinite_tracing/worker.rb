# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

# The Worker class makes it easy to stop and start a thread at will.
# Some basic error handling/capture is wrapped around the Thread to help 
# propagate the exceptions arising from the threaded processes to the main process
# where the main agent code lives.
module NewRelic::Agent
  module InfiniteTracing

    class Worker
      attr_reader :name, :error

      def initialize name, &job
        @name = name
        @job = job
        @error = nil
        @worker_thread = nil
        @lock = Mutex.new
        @lock.synchronize { start_thread }
      end

      def status
        return "error" if error?
        @lock.synchronize do
          return "stopped" if @worker_thread.nil?
          @worker_thread.status || "idle"
        end
      end

      def error?
        !!@error
      end

      def join timeout=nil
        return unless @worker_thread
        @worker_thread.join timeout
      end

      def stop
        @lock.synchronize do 
          return unless @worker_thread
          NewRelic::Agent.logger.debug "stopping worker #{@name} thread..."
          @worker_thread.kill
          @worker_thread = nil
        end
      end

      private

      def start_thread
        NewRelic::Agent.logger.debug "starting worker #{@name} thread..."
        @worker_thread = Thread.new do
          catch(:exit) do
            begin
              @job.call
            rescue => err
              @error = err
              raise
            end
          end
        end
        @worker_thread.abort_on_exception = true
        if @worker_thread.respond_to? :report_on_exception
          @worker_thread.report_on_exception = NewRelic::Agent.config[:log_level] == "debug"
        end
      end
    end

  end
end