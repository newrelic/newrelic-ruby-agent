require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/configuration/yaml_source'

module NewRelic::Agent::Configuration
  class YamlSourceTest < Test::Unit::TestCase
    def setup
      test_yml_path = File.expand_path(File.join(File.dirname(__FILE__),
                                                 '..','..','..',
                                                 'config','newrelic.yml'))
      @source = YamlSource.new(test_yml_path, 'test')
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
      assert_not_equal 'the.wrong.host', @source[:host]
    end

    def test_should_convert_to_dot_notation
      assert_equal 'raw', @source[:'transaction_tracer.record_sql']
    end

    def test_should_ignore_apdex_f_setting_for_transaction_threshold
      assert_equal nil, @source[:'transaction_tracer.transaction_threshold']
    end

    def test_should_correctly_handle_floats
      assert_equal 1.1, @source[:apdex_t]
    end

    def test_should_log_if_no_file_is_found
      NewRelic::Control.instance.log.expects(:error)
      source = YamlSource.new('no_such_file.yml', 'test')
    end
  end
end
