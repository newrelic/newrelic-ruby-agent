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

    attr_reader :data
    # Generate the report based on the class level logic.
    def initialize
      @data = self.class.report_logic.inject(Hash.new) do |data, (key, logic)|
        begin
          value = logic.call
          data[key] = value if value
        rescue => e
          Agent.logger.debug("Couldn't retrieve value for #{key.inspect}: #{e}")
        end
        data
      end
    end

    report_on 'Gems' do
      Bundler.rubygems.all_specs.map { |gem| "#{gem.name} (#{gem.version})" }
    end

    report_on 'Plugin List' do
      ::Rails.configuration.plugins.to_a
    end

    def [](key)
      @data[key]
    end

    def []=(key, value)
      @data[key] = value
    end
  end
end
