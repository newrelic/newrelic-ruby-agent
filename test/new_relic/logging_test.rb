# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','test_helper'))
require 'stringio'
require 'json'

module NewRelic
  module Logging
    class LoggingTest < Minitest::Test

      def setup
        @output = StringIO.new
      end

      def test_log_to_json
        logger = DecoratingLogger.new @output
        logger.info('this is a test')

        message = JSON.load @output.string
        # Should include the keys:
        #  entity.name, entity.type, hostname, timestamp, message, log.level
        assert_equal 'this is a test', message['message']
        assert_equal 'INFO', message['log.level']

        assert_includes message, 'entity.name'
        refute_nil message['entity.name']

        assert_includes message, 'entity.type'
        refute_nil message['entity.type']

        assert_includes message, 'hostname'
        refute_nil message['hostname']

        assert_includes message, 'timestamp'
        refute_nil message['timestamp']

      end

      def test_constructor_arguments_shift_age
        shift_age = 350
        shift_size = 10000
        logger = DecoratingLogger.new '/tmp/tmp.log', shift_age = 30, shift_size = 1000
        device = logger.instance_variable_get :@logdev
        assert_equal '/tmp/tmp.log', device.instance_variable_get(:@filename)
        assert_equal 30, device.instance_variable_get(:@shift_age)
        assert_equal 1000, device.instance_variable_get(:@shift_size)
      end

      def test_constructor_arguments_level
        logger = DecoratingLogger.new @output, level: :error
        assert_equal Logger::ERROR, logger.level
      end

      def test_constructor_arguments_progname
        logger = DecoratingLogger.new @output, progname: 'LoggingTest'
        logger.info('test')

        message = JSON.load @output.string
        assert_equal 'LoggingTest', message['logger.name']
      end

      def test_constructor_arguments_formatter
        # the formatter parameter is ignored, in favor of our formatter.
        # does this seem correct?  Maybe if they pass one in, we should keep
        # it and use it to format messages?
        formatter = ::Logger::Formatter.new
        logger = DecoratingLogger.new @output, formatter: formatter
        refute_equal formatter, logger.formatter
      end
    end
  end
end
