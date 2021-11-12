# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require 'new_relic/agent/sampler'

module NewRelic
  module Agent
    module Samplers
      class MemorySampler < NewRelic::Agent::Sampler
        named :memory

        attr_accessor :sampler

        def initialize
          @sampler = nil

          # macos, linux, solaris
          if defined? JRuby
            @sampler = JavaHeapSampler.new
          elsif platform =~ /linux/
            @sampler = ProcStatus.new
            if !@sampler.can_run?
              ::NewRelic::Agent.logger.debug "Error attempting to use /proc/#{$$}/status file for reading memory. Using ps command instead."
              @sampler = ShellPS.new('ps -o rsz')
            else
              ::NewRelic::Agent.logger.debug "Using /proc/#{$$}/status for reading process memory."
            end
          elsif platform =~ /darwin9/ # 10.5
            @sampler = ShellPS.new('ps -o rsz')
          elsif platform =~ /darwin(1|2)\d+/ # >= 10.6
            @sampler = ShellPS.new('ps -o rss')
          elsif platform =~ /freebsd/
            @sampler = ShellPS.new('ps -o rss')
          elsif platform =~ /solaris/
            @sampler = ShellPS.new('/usr/bin/ps -o rss -p')
          end

          raise Unsupported, "Unsupported platform for getting memory: #{platform}" if @sampler.nil?
          raise Unsupported, "Unable to run #{@sampler}" unless @sampler.can_run?
        end

        def self.supported_on_this_platform?
          defined?(JRuby) or platform =~ /linux|darwin|freebsd|solaris/
        end

        def self.platform
          if RUBY_PLATFORM =~ /java/
            `uname -s`.downcase
          else
            RUBY_PLATFORM.downcase
          end
        end

        def platform
          NewRelic::Agent::Samplers::MemorySampler.platform
        end

        def poll
          sample = @sampler.get_sample
          NewRelic::Agent.record_metric('Memory/Physical', sample) if sample
        end

        class Base
          def initialize
            @broken = false
          end

          def can_run?
            return false if @broken

            m = begin
              get_memory
            rescue StandardError
              nil
            end
            m && m > 0
          end

          def get_sample
            return nil if @broken

            begin
              m = get_memory
              if m.nil?
                ::NewRelic::Agent.logger.warn "Unable to get the resident memory for process #{$$}.  Disabling memory sampler."
                @broken = true
              end
              m
            rescue StandardError => e
              ::NewRelic::Agent.logger.warn "Unable to get the resident memory for process #{$$}. Disabling memory sampler.",
                                            e
              @broken = true
              nil
            end
          end
        end

        class JavaHeapSampler < Base
          def get_memory
            raise "Can't sample Java heap unless running in JRuby" unless defined? JRuby

            begin
              java.lang.Runtime.getRuntime.totalMemory / (1024 * 1024).to_f
            rescue StandardError
              nil
            end
          end

          def to_s
            'JRuby Java heap sampler'
          end
        end

        class ShellPS < Base
          def initialize(command)
            super()
            @command = command
          end

          # Returns the amount of resident memory this process is using in MB
          #
          def get_memory
            process = $$
            memory = begin
              `#{@command} #{process}`.split("\n")[1].to_f / 1024.0
            rescue StandardError
              nil
            end
            # if for some reason the ps command doesn't work on the resident os,
            # then don't execute it any more.
            raise "Faulty command: `#{@command} #{process}`" if memory.nil? || memory <= 0

            memory
          end

          def to_s
            "shell command sampler: #{@command}"
          end
        end

        # ProcStatus
        #
        # A class that samples memory by reading the file /proc/$$/status, which is specific to linux
        #
        class ProcStatus < Base
          # Returns the amount of resident memory this process is using in MB
          def get_memory
            proc_status = File.open(proc_status_file, 'r') { |f| f.read_nonblock(4096).strip }
            return Regexp.last_match(1).to_f / 1024.0 if proc_status =~ /RSS:\s*(\d+) kB/i

            raise "Unable to find RSS in #{proc_status_file}"
          end

          def proc_status_file
            "/proc/#{$$}/status"
          end

          def to_s
            "proc status file sampler: #{proc_status_file}"
          end
        end
      end
    end
  end
end
