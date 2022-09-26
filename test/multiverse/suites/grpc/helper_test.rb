# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'newrelic_rpm'

class GrpcHelperTest < Minitest::Test
  include MultiverseHelpers

  class HelpedClass
    include NewRelic::Agent::Instrumentation::GRPC::Helper
  end

  def unwanted_host_patterns
    [/unwanted/.freeze].freeze
  end

  def helped_class
    HelpedClass.new
  end

  def test_cleans_method_names
    input = '/method/with/leading/slash'
    output = 'method/with/leading/slash'
    assert_equal output, helped_class.cleaned_method(input)
  end

  def test_cleans_method_names_as_symbols
    input = :'/method/with/leading/slash'
    output = 'method/with/leading/slash'
    assert_equal output, helped_class.cleaned_method(input)
  end

  def test_does_not_clean_methods_that_do_not_need_cleaning
    input = 'method/without/leading/slash'
    assert_equal input, helped_class.cleaned_method(input)
  end

  def test_confirms_that_host_is_not_on_the_config_defined_denylist
    mock = MiniTest::Mock.new
    mock.expect(:[], unwanted_host_patterns, [:'instrumentation.grpc.host_denylist'])
    NewRelic::Agent.stub(:config, mock) do
      refute helped_class.host_denylisted?('wanted_host')
    end
  end

  def test_confirms_that_host_is_denylisted_from_config
    mock = MiniTest::Mock.new
    mock.expect(:[], unwanted_host_patterns, [:'instrumentation.grpc.host_denylist'])
    NewRelic::Agent.stub(:config, mock) do
      assert helped_class.host_denylisted?('unwanted_host')
    end
  end

  def test_confirms_that_host_is_denylisted_for_8t
    NewRelic::Agent::Instrumentation::GRPC::Helper.stub_const(:NR_8T_HOST_PATTERN, '8t') do
      assert helped_class.host_denylisted?('an_8t_host')
    end
  end
end
