# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

module NewRelic
  module Agent

    # Handles loading of ignored and expected errors from the agent configuration, and
    # determining at runtime whether an exception is ignored or expected.
    class ErrorFilter

      def initialize
        @ignore_errors, @ignore_classes, @expected_classes = [], [], []
        @ignore_messages, @expected_messages = {}, {}
        @ignore_status_codes, @expected_status_codes = [], []
      end

      def load_all
        %i(
          ignore_errors ignore_classes ignore_messages ignore_status_codes
          expected_classes expected_messages expected_status_codes
        ).each { |setting| load_from_config(setting) }
      end

      def load_from_config(setting, value = nil)
        errors = nil
        new_value = value || fetch_agent_config(setting.to_sym)
        case setting.to_sym
        when :ignore_errors  # Deprecated; only use if ignore_classes isn't present
          errors = @ignore_errors = new_value.to_s.split(',').map!(&:strip)
        when :ignore_classes
          errors = @ignore_classes = new_value || []
        when :ignore_messages
          errors = @ignore_messages = new_value || {}
        when :ignore_status_codes
          errors = @ignore_status_codes = parse_status_codes(new_value) || []
        when :expected_classes
          errors = @expected_classes = new_value || []
        when :expected_messages
          errors = @expected_messages = new_value || {}
        when :expected_status_codes
          errors = @expected_status_codes = parse_status_codes(new_value) || []
        end
        log_filter(setting, errors)
      end

      # Define #ignored? and #expected? in this way so that any given exception
      # cannot be both ignored and expected when using type_for_exception.
      # Ignoring takes priority.

      def ignore?(ex)
        @ignore_classes.include?(ex.class.name) || 
          (@ignore_classes.empty? && @ignore_errors.include?(ex.class.name)) ||
          @ignore_messages.keys.include?(ex.class.name) &&
          @ignore_messages[ex.class.name].any? { |m| ex.message.include?(m) }
      end

      def expected?(ex)
        @expected_classes.include?(ex.class.name) ||
        @expected_messages.keys.include?(ex.class.name) &&
        @expected_messages[ex.class.name].any? { |m| ex.message.include?(m) }
      end

      def fetch_agent_config(cfg)
        NewRelic::Agent.config[:"error_collector.#{cfg}"]
      end

      def ignore(errors)
        case errors
        when Array
          @ignore_classes += errors
          log_filter(:ignore_classes, errors)
        when Hash
          @ignore_messages.update(errors)
          log_filter(:ignore_messages, errors)
        when String
          if errors.match(/^[\d\,\-]+$/)
            @ignore_status_codes += parse_status_codes(errors)  # TODO: convert this value to a Hash
          else
            new_ignore_classes = errors.split(',').map!(&:strip)
            @ignore_classes += new_ignore_classes
            log_filter(:ignore_classes, new_ignore_classes)
          end
        end
      end

      def expect(errors)
        case errors
        when Array
          @expected_classes += errors
          log_filter(:expected_classes, errors)
        when Hash
          @expected_messages.update(errors)
          log_filter(:expected_messages, errors)
        when String
          if errors.match(/^[\d\,\-]+$/)
            @expected_status_codes += parse_status_codes(errors)
          else
            new_expected_classes = errors.split(',').map!(&:strip)
            @expected_classes += new_expected_classes
            log_filter(:expected_classes, new_expected_classes)
          end
        end
      end

      private

      def log_filter(setting, errors)
        case setting
        when :ignore_errors, :ignore_classes
          errors.each do |error|
            ::NewRelic::Agent.logger.debug("Ignoring errors of type '#{error}'")
          end
        when :ignore_messages
          errors.each do |error,messages|
            ::NewRelic::Agent.logger.debug("Ignoring errors of type '#{error}' with messages: #{messages.join(',')}")
          end
        when :ignore_status_codes
          ::NewRelic::Agent.logger.debug("Ignoring errors associated with status codes: #{errors}")
        when :expected_classes
          errors.each do |error|
            ::NewRelic::Agent.logger.debug("Expecting errors of type '#{error}'")
          end
        when :expected_messages
          errors.each do |error,messages|
            ::NewRelic::Agent.logger.debug("Expecting errors of type '#{error}' with messages: #{messages.join(',')}")
          end
        when :expected_status_codes
          ::NewRelic::Agent.logger.debug("Expecting errors associated with status codes: #{errors}")
        end
      end

      def parse_status_codes(code_string)
        # TODO: implement
        []
      end
    end
  end
end