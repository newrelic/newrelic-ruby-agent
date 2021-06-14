# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

module NewRelic
  module Agent

    # Handles loading of ignored and expected errors from the agent configuration, and
    # determining at runtime whether an exception is ignored or expected.
    class ErrorFilter
      def initialize
        reload
      end

      # Load ignored/expected errors from current agent config
      def reload
        @ignored_classes      = fetch_agent_config(:ignore_classes) || []
        @ignored_messages     = fetch_agent_config(:ignore_messages) || {}
        @ignored_status_codes = fetch_agent_config(:ignore_status_codes) || ''

        @expected_classes      = fetch_agent_config(:expected_classes) || []
        @expected_messages     = fetch_agent_config(:expected_messages) || {}
        @expected_status_codes = fetch_agent_config(:expected_status_codes) || ''

        # error_collector.ignore_errors is deprecated, but we still support it
        if @ignored_classes.empty? && ignore_errors = fetch_agent_config(:ignore_errors)
          @ignored_classes << ignore_errors.split(',').map!(&:strip)
          @ignored_classes.flatten!
        end

        log_filters
      end

      # Takes an Exception object. Depending on whether the Agent is configured
      # to treat the exception as Ignored, Expected or neither, returns :ignored,
      # :expected or nil, respectively.
      def type_for_exception(ex)
        return nil unless ex.is_a?(Exception)
        return :ignored if _ignored?(ex)
        return :expected if _expected?(ex)
        nil
      end

      # Define #ignored? and #expected? in this way so that any given exception
      # cannot be both ignored and expected. Ignoring takes priority.

      def ignored?(ex)
        type_for_exception(ex) == :ignored
      end

      def expected?(ex)
        type_for_exception(ex) == :expected
      end

      def fetch_agent_config(cfg)
        NewRelic::Agent.config[:"error_collector.#{cfg}"]
      end

      private

      def _ignored?(ex)
        @ignored_classes.include?(ex.class.name) ||
          @ignored_messages.keys.include?(ex.class.name) &&
          @ignored_messages[ex.class.name].any? { |m| ex.message.include?(m) }
      end

      def _expected?(ex)
        @expected_classes.include?(ex.class.name) ||
          @expected_messages.keys.include?(ex.class.name) &&
          @expected_messages[ex.class.name].any? { |m| ex.message.include?(m) }
      end

      def log_filters
        @ignored_classes.each do |c|
          ::NewRelic::Agent.logger.debug("Ignoring errors of type '#{c}'")
        end
        @ignored_messages.each do |k,v|
          ::NewRelic::Agent.logger.debug("Ignoring errors of type '#{k}' with messages: " + v.join(', '))
        end
        ::NewRelic::Agent.logger.debug("Ignoring status codes #{@ignored_status_codes}") unless @ignored_status_codes.empty?

        @expected_classes.each do |c|
          ::NewRelic::Agent.logger.debug("Expecting errors of type '#{c}'")
        end
        @expected_messages.each do |k,v|
          ::NewRelic::Agent.logger.debug("Expecting errors of type '#{k}' with messages: " + v.join(', '))
        end
        ::NewRelic::Agent.logger.debug("Expecting status codes #{@expected_status_codes}") unless @expected_status_codes.empty?
      end
    end
  end
end