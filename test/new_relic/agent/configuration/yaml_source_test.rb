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
      assert_equal '127.0.0.1', @source['api_host']
    end

    def test_should_apply_erb_transformations
      assert_equal 'heyheyhey', @source['erb_value']
    end

    def test_should_load_the_config_for_the_correct_env
      assert_not_equal 'the.wrong.host', @source['host']
    end

    def test_should_convert_to_dot_notation
      assert_equal 'raw', @source['transaction_tracer.record_sql']
    end

    def test_should_be_immutable
      assert_raises RuntimeError, TypeError do
        @source['host'] = 'somewhere.else'
      end
    end
  end
end
