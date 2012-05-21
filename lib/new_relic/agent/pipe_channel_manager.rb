module NewRelic
  module Agent
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
        attr_accessor :out
        attr_accessor :in
        
        def initialize
          @out, @in = IO.pipe
          if defined?(::Encoding::ASCII_8BIT)
            @in.set_encoding(::Encoding::ASCII_8BIT)
          end
        end
        
        def close
          @out.close unless @out.closed?
          @in.close unless @in.closed?
        end

        def write(data)
          @out.close unless @out.closed?
          @in << data
        end
      end
      
      class Listener
        attr_reader   :thread
        attr_accessor :pipes

        def initialize
          @pipes = {}
        end

        def register_pipe(id)
          @pipes[id] = Pipe.new
          wake.in << '.'
        end

        def start
          return if @started == true
          @started = true
          @thread = Thread.new do
            loop do
              clean_up_pipes
              pipes_to_listen_to = @pipes.values.map{|pipe| pipe.out} + [wake.out]
              if ready = IO.select(pipes_to_listen_to)[0][0]
                if ready == wake.out
                  ready.read(1)
                  next if should_keep_listening? # found a new pipe, restart select
                else
                  close_in_handle_for(ready)
                  got = ready.read
                  if got.empty? && ready.eof?
                    ready.close
                    next if should_keep_listening? # this pipe done, move on
                  end
                
                  payload = Marshal.load(got)
                  NewRelic::Agent.agent.merge_data_from([payload[:stats],
                                                  payload[:transaction_traces],
                                                  payload[:error_traces]])
                  ready.close
                end
                break if !should_keep_listening?
              end
            end
          end
          sleep 0.001 # give time for the thread to spawn
        end

        def should_keep_listening?
          @started || @pipes.values.find{|pipe| !pipe.in.closed?}
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
        
        def clean_up_pipes
          @pipes.reject! {|id, pipe| pipe.out.closed? }
        end

        def close_in_handle_for(out_handle)
          pipe = @pipes.values.find{|pipe| pipe.out == out_handle }
          if pipe
            pipe.in.close unless pipe.in.closed?
          end
        end
      end
    end
  end
end
