# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'base64'

module NewRelic
  module Agent

    #--
    # Manages the registering and servicing of pipes used by child
    # processes to report data to their parent, rather than directly
    # to the collector.
    module PipeChannelManager
      extend self

      def register_report_channel(id)
        listener.register_pipe(id)
      end

      def channels
        listener.pipes
      end

      def listener
        @listener ||= Listener.new
      end

      # Expected initial sequence of events for Pipe usage:
      #
      # 1. Pipe is created in parent process (read and write ends open)
      # 2. Parent process forks
      # 3. An after_fork hook is invoked in the child
      # 4. From after_fork hook, child closes read end of pipe, and
      #    writes a ready marker on the pipe (after_fork_in_child).
      # 5. The parent receives the ready marker, and closes the write end of the
      #    pipe in response (after_fork_in_parent).
      #
      # After this sequence of steps, an exit (whether clean or not) of the
      # child will result in the pipe being marked readable again, and giving an
      # EOF marker (nil) when read. Note that closing of the unused ends of the
      # pipe in the parent and child processes is essential in order for the EOF
      # to be correctly triggered. The ready marker mechanism is used because
      # there's no easy hook for after_fork in the parent process.
      class Pipe
        READY_MARKER = "READY"

        attr_accessor :in, :out
        attr_reader :last_read, :parent_pid

        def initialize
          @out, @in = IO.pipe
          if defined?(::Encoding::ASCII_8BIT)
            @in.set_encoding(::Encoding::ASCII_8BIT)
          end
          @last_read = Time.now
          @parent_pid = $$
        end

        def close
          @out.close unless @out.closed?
          @in.close unless @in.closed?
        end

        def write(data)
          @out.close unless @out.closed?
          @in << NewRelic::LanguageSupport.with_cautious_gc do
            Marshal.dump(data)
          end
          @in << "\n\n"
        end

        def read
          @in.close unless @in.closed?
          @last_read = Time.now
          @out.gets("\n\n")
        end

        def eof?
          !@out.closed? && @out.eof?
        end

        def after_fork_in_child
          @out.close unless @out.closed?
          write(READY_MARKER)
        end

        def after_fork_in_parent
          @in.close unless @in.closed?
        end

        def closed?
          @out.closed? && @in.closed?
        end
      end

      class Listener
        attr_reader   :thread
        attr_accessor :pipes, :timeout, :select_timeout

        def initialize
          @pipes = {}
          @timeout = 360
          @select_timeout = 60
        end

        def wakeup
          wake.in << '.'
        end

        def register_pipe(id)
          @pipes[id] = Pipe.new
          wakeup
        end

        def start
          return if @started == true
          @started = true
          @thread = NewRelic::Agent::Threading::AgentThread.new('Pipe Channel Manager') do
            now = nil
            loop do
              clean_up_pipes
              pipes_to_listen_to = @pipes.values.map{|pipe| pipe.out} + [wake.out]

              NewRelic::Agent.record_metric('Supportability/Listeners',
                (Time.now - now).to_f) if now

              if ready = IO.select(pipes_to_listen_to, [], [], @select_timeout)
                now = Time.now

                ready_pipes = ready[0]
                ready_pipes.each do |pipe|
                  merge_data_from_pipe(pipe) unless pipe == wake.out
                end

                wake.out.read(1) if ready_pipes.include?(wake.out)
              end

              break unless should_keep_listening?
            end
          end
          sleep 0.001 # give time for the thread to spawn
        end

        def stop_listener_thread
          @started = false
          wakeup
          @thread.join
        end

        def stop
          return unless @started == true
          stop_listener_thread
          close_all_pipes
          @wake.close
          @wake = nil
        end

        def close_all_pipes
          @pipes.each do |id, pipe|
            pipe.close if pipe
          end
          @pipes = {}
        end

        def wake
          @wake ||= Pipe.new
        end

        def started?
          @started
        end

        protected

        def merge_data_from_pipe(pipe_handle)
          pipe = find_pipe_for_handle(pipe_handle)
          raw_payload = pipe.read

          if raw_payload && !raw_payload.empty?
            payload = unmarshal(raw_payload)
            if payload == Pipe::READY_MARKER
              pipe.after_fork_in_parent
            elsif payload
              NewRelic::Agent.agent.merge_data_from([payload[:stats],
                                                     payload[:transaction_traces],
                                                     payload[:error_traces]])
            end
          end

          pipe.close if pipe.eof?
        end

        def unmarshal(data)
          NewRelic::LanguageSupport.with_cautious_gc do
            Marshal.load(data)
          end
        rescue StandardError => e
          msg = "#{e.class.name} '#{e.message}' trying to load #{Base64.encode64(data)}"
          ::NewRelic::Agent.logger.debug(msg)
          nil
        end

        def should_keep_listening?
          @started || @pipes.values.find{|pipe| !pipe.in.closed?}
        end

        def clean_up_pipes
          @pipes.values.each do |pipe|
            if pipe.last_read.to_f + @timeout < Time.now.to_f
              pipe.close unless pipe.closed?
            end
          end
          @pipes.reject! {|id, pipe| pipe.out.closed? }
        end

        def find_pipe_for_handle(out_handle)
          @pipes.values.find{|pipe| pipe.out == out_handle }
        end
      end
    end
  end
end
