# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
require 'pry'

module NewRelic
  module Agent

    # Handles loading of ignored and expected errors from the agent configuration, and
    # determining at runtime whether an exception is ignored or expected.
    class ErrorFilter

      def initialize
        reset
      end

      def reset
        @ignore_classes, @expected_classes = [], []
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
        #edit 33 to account for integer (DONE)
        
        return if new_value.nil? || (new_value.instance_of?(String) && new_value.empty?) 

        case setting.to_sym
        when :ignore_errors, :ignore_classes
          new_value = new_value.split(',').map!(&:strip) if new_value.is_a?(String)
          errors = @ignore_classes = new_value
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
        log_filter(setting, errors) if errors
      end

      def ignore?(ex, status_code = nil)
        @ignore_classes.include?(ex.class.name) || 
          (@ignore_messages.keys.include?(ex.class.name) &&
          @ignore_messages[ex.class.name].any? { |m| ex.message.include?(m) }) ||
          @ignore_status_codes.include?(status_code.to_i)
      end

      def expected?(ex, status_code = nil)
        @expected_classes.include?(ex.class.name) ||
          (@expected_messages.keys.include?(ex.class.name) &&
          @expected_messages[ex.class.name].any? { |m| ex.message.include?(m) }) ||
          @expected_status_codes.include?(status_code.to_i)
      end

      def fetch_agent_config(cfg)
        NewRelic::Agent.config[:"error_collector.#{cfg}"]
      end

      # A generic method for adding ignore filters manually. This is kept for compatibility
      # with the previous ErrorCollector#ignore method, and adds some flexibility for adding
      # different ignore/expected error types by examining each argument.
      def ignore(*args)
        args.each do |errors|
          case errors
          when Array
            errors.each { |e| ignore(e) }
          when Integer
            @ignore_status_codes << errors
          when Hash
            @ignore_messages.update(errors)
            log_filter(:ignore_messages, errors)
          when String
            if errors.match(/^[\d\,\-]+$/)
              @ignore_status_codes |= parse_status_codes(errors)
              log_filter(:ignore_status_codes, errors)
            else
              new_ignore_classes = errors.split(',').map!(&:strip)
              @ignore_classes |= new_ignore_classes
              log_filter(:ignore_classes, new_ignore_classes)
            end
          end
        end
      end

      # See #ignore above.
      def expect(*args)
        args.each do |errors|
          case errors
          when Array
            errors.each { |e| expect(e) }
          when Integer
            @expected_status_codes << errors
          when Hash
            @expected_messages.update(errors)
            log_filter(:expected_messages, errors)
          when String
            if errors.match(/^[\d\,\-]+$/)
              @expected_status_codes |= parse_status_codes(errors)
              log_filter(:expected_status_codes, errors)
            else
              new_expected_classes = errors.split(',').map!(&:strip)
              @expected_classes |= new_expected_classes
              log_filter(:expected_classes, new_expected_classes)
            end
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

      #edit this to account for integers 
      def parse_status_codes(codes)
        # Refactor this to make the integer go into an array so that we can do the .each method (DONE)
        code_list = codes.is_a?(String) ? codes.split(',') : codes.is_a?(Integer) ? [codes] : codes
        result = []
        code_list.each do |code|
          result << code && next if code.is_a?(Integer)
          #what to do when code is a integer? return just code or something else? 
          m = code.match(/(\d{3})(-\d{3})?/) 
          if m.nil? || m[1].nil?
            ::NewRelic::Agent.logger.warn("Invalid HTTP status code: '#{code}'; ignoring config")
            next
          end
          if m[2]
            result += (m[1]..m[2].tr('-', '')).to_a.map(&:to_i)
          else
            result << m[1].to_i
          end
        end
        result.uniq
      end
    end
  end
end