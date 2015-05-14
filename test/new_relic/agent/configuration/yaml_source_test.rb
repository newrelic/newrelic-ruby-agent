# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/configuration/yaml_source'

module NewRelic::Agent::Configuration
  class YamlSourceTest < Minitest::Test
    def setup
      @test_yml_path = File.expand_path(File.join(File.dirname(__FILE__),
                                                 '..','..','..',
                                                 'config','newrelic.yml'))
      @source = YamlSource.new(@test_yml_path, 'test')
    end

    def test_should_load_given_yaml_file
      assert_equal '127.0.0.1', @source[:api_host]
    end

    def test_should_apply_erb_transformations
      assert_equal 'heyheyhey', @source[:erb_value]
      assert_equal '', @source[:message]
      assert_equal '', @source[:license_key]
    end

    def test_config_booleans
      assert_equal true, @source[:tval]
      assert_equal false, @source[:fval]
      assert_nil @source[:not_in_yaml_val]
      assert_equal true, @source[:yval]
      assert_equal 'sure', @source[:sval]
    end

    def test_appnames
      assert_equal %w[a b c], @source[:app_name]
    end

    def test_should_load_the_config_for_the_correct_env
      refute_equal 'the.wrong.host', @source[:host]
    end

    def test_should_convert_to_dot_notation
      assert_equal 'raw', @source[:'transaction_tracer.record_sql']
    end

    def test_should_still_have_nested_hashes_around
      refute_nil @source[:transaction_tracer]
    end

    def test_should_ignore_apdex_f_setting_for_transaction_threshold
      assert_equal nil, @source[:'transaction_tracer.transaction_threshold']
    end

    def test_should_correctly_handle_floats
      assert_equal 1.1, @source[:apdex_t]
    end

    def test_should_not_log_error_by_default
      expects_no_logging(:error)
      YamlSource.new(@test_yml_path, 'test')
    end

    def test_should_log_if_no_file_is_found
      expects_logging(:warn, any_parameters)
      YamlSource.new('no_such_file.yml', 'test')
    end

    def test_should_log_if_environment_is_not_present
      expects_logging(:error, includes(@test_yml_path))
      YamlSource.new(@test_yml_path, 'nonsense')
    end

    def test_should_not_fail_to_log_missing_file_during_startup
      without_logger do
        ::NewRelic::Agent::StartupLogger.any_instance.expects(:warn)
        YamlSource.new('no_such_file.yml', 'test')
      end
    end

    def test_should_not_fail_to_log_invalid_file_during_startup
      without_logger do
        ::NewRelic::Agent::StartupLogger.any_instance.expects(:error)

        File.stubs(:exist?).returns(true)
        File.stubs(:read).raises(StandardError.new("boo"))

        YamlSource.new('fake.yml', 'test')
      end
    end

    def test_should_mark_error_on_read_as_failure
      File.stubs(:exist?).returns(true)
      File.stubs(:read).raises(StandardError.new("boo"))

      source = YamlSource.new('fake.yml', 'test')
      assert source.failed?
    end

    def test_should_mark_erb_error_as_failure
      ERB.stubs(:new).raises(StandardError.new("boo"))

      source = YamlSource.new(@test_yml_path, 'test')
      assert source.failed?
    end

    def test_should_mark_missing_section_as_failure
      source = YamlSource.new(@test_yml_path, 'yolo')
      assert source.failed?
    end

    def test_failure_should_include_message
      source = YamlSource.new(@test_yml_path, 'yolo')
      assert_includes source.failures.flatten.join(' '), 'yolo'
    end
  end
end
