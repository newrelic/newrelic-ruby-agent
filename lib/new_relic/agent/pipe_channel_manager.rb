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

      class Pipe
        attr_accessor :in, :out
        attr_reader :last_read

        def initialize
          @out, @in = IO.pipe
          if defined?(::Encoding::ASCII_8BIT)
            @in.set_encoding(::Encoding::ASCII_8BIT)
          end
          @last_read = Time.now
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

        def register_pipe(id)
          @pipes[id] = Pipe.new
          wake.in << '.'
        end

        def start
          return if @started == true
          @started = true
          @thread = Thread.new do
            now = nil
            loop do
              clean_up_pipes
              pipes_to_listen_to = @pipes.values.map{|pipe| pipe.out} + [wake.out]
              NewRelic::Agent.instance.stats_engine \
                .get_stats_no_scope('Supportability/Listeners') \
                .record_data_point((Time.now - now).to_f) if now
              if ready = IO.select(pipes_to_listen_to, [], [], @select_timeout)
                now = Time.now
                pipe = ready[0][0]
                if pipe == wake.out
                  pipe.read(1)
                else
                  merge_data_from_pipe(pipe)
                end
              end

              break if !should_keep_listening?
            end
          end
          @thread['newrelic_label'] = 'Pipe Channel Manager'
          sleep 0.001 # give time for the thread to spawn
        end

        def stop
          return unless @started == true
          @started = false
          wake.in << '.' unless wake.in.closed?
          @thread.join # make sure we wait for the thread to exit
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
          got = pipe.read

          if got && !got.empty?
            payload = unmarshal(got)
            if payload == 'EOF'
              pipe.close
            elsif payload
              NewRelic::Agent.agent.merge_data_from([payload[:stats],
                                                     payload[:transaction_traces],
                                                     payload[:error_traces]])
            end
          end
        end

        def unmarshal(data)
          NewRelic::LanguageSupport.with_cautious_gc do
            Marshal.load(data)
          end
        rescue StandardError => e
          msg = "#{e.class.name} '#{e.message}' trying to load #{Base64.encode64(data)}"
          NewRelic::Control.instance.log.debug(msg)
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
