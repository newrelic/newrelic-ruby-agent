# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  # The EnvironmentReport is responsible for analyzing the application's
  # environment and generating the data for the Environment Report in New
  # Relic's interface.
  #
  # It contains useful system information like Ruby version, OS, loaded gems,
  # etc.
  #
  # Additional logic can be registered by using the EnvironmentReport.report_on
  # hook.
  class EnvironmentReport

    # This is the main interface for registering logic that should be included
    # in the Environment Report. For example:
    #
    # EnvironmentReport.report_on "Day of week" do
    #   Time.now.strftime("%A")
    # end
    #
    # The passed blocks will be run in EnvironmentReport instances on #initialize.
    #
    # Errors raised in passed blocks will be handled and logged at debug, so it
    # is safe to report on things that may not work in certain environments.
    def self.report_on(key, &block)
      report_logic[key] = block
    end

    def self.report_logic
      @report_logic ||= Hash.new
    end

    # allow the logic to be swapped out in tests
    def self.report_logic=(logic)
      @report_logic = logic
    end

    # register reporting logic
    ####################################
    report_on 'Gems' do
      Bundler.rubygems.all_specs.map { |gem| "#{gem.name} (#{gem.version})" }
    end
    report_on('Plugin List'){ ::Rails.configuration.plugins.to_a }
    report_on('Ruby version'){ RUBY_VERSION }
    report_on('Ruby description'){ RUBY_DESCRIPTION }
    report_on('Ruby platform'){ RUBY_PLATFORM }
    report_on('Ruby patchlevel'){ RUBY_PATCHLEVEL.to_s }
    report_on('JRuby version') { JRUBY_VERSION }
    report_on('Java VM version') { ENV_JAVA['java.vm.version']}
    report_on 'Processors' do
      cpuinfo = ''
      proc_file = '/proc/cpuinfo'
      File.open(proc_file) do |f|
        loop do
          begin
            cpuinfo << f.read_nonblock(4096).strip
          rescue EOFError
            break
          rescue Errno::EWOULDBLOCK, Errno::EAGAIN
            cpuinfo = ''
            break # don't select file handle, just give up
          end
        end
      end
      processors = cpuinfo.split("\n").select {|line| line =~ /^processor\s*:/ }.size

      if processors == 0
        processors = nil # assume there is at least one processor
        ::NewRelic::Agent.logger.warn("Cannot determine the number of processors in #{proc_file}")
      end
      processors
    end
    report_on 'Arch' do
      arch = `uname -p`
      arch = ENV['PROCESSOR_ARCHITECTURE'] if arch == ''
      arch
    end
    report_on('OS version'){ `uname -v` }
    report_on('OS') do
      os = `uname -s`
      os = ENV['OS'] if os == ''
      os
    end
    report_on('Hostname'){ `hostname` }
    report_on('User'){ `whoami` }
    report_on 'Database adapter' do
      ActiveRecord::Base.configurations[NewRelic::Control.instance.env]['adapter']
    end
    report_on('Framework') { Agent.config[:framework].to_s }
    report_on('Dispatcher') { Agent.config[:dispatcher].to_s }
    report_on('Environment') { NewRelic::Control.instance.env }
    report_on('Rails version') { ::Rails::VERSION::STRING }
    report_on 'Rails threadsafe' do
      ::Rails.configuration.action_controller.allow_concurrency
    end
    report_on 'Rails Env' do
      if defined? ::Rails and ::Rails.respond_to?(:env)
        ::Rails.env
      else
        ENV['RAILS_ENV']
      end
    end
    # end reporting logic
    ####################################


    attr_reader :data
    # Generate the report based on the class level logic.
    def initialize
      @data = self.class.report_logic.inject(Hash.new) do |data, (key, logic)|
        begin
          value = logic.call
          if value
            data[key] = value
          else
            Agent.logger.debug("Retrieved value for #{key.inspect} but got #{value.inspect}")
          end
        rescue => e
          Agent.logger.debug("Couldn't retrieve value for #{key.inspect}: #{e}")
        end
        data
      end
    end

    def [](key)
      @data[key]
    end

    def []=(key, value)
      @data[key] = value
    end

    def to_a
      @data.to_a
    end
  end
end
