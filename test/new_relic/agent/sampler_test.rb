# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'test_helper'))
class NewRelic::Agent::SamplerTest < Minitest::Test
  require 'new_relic/agent/sampler'

  class UnnamedSampler < NewRelic::Agent::Sampler
    def poll; end
  end

  class DummySampler < NewRelic::Agent::Sampler
    named :dummy

    def poll; end
  end

  def test_inherited_should_append_subclasses_to_sampler_classes
    test_class = Class.new(NewRelic::Agent::Sampler)
    sampler_classes = NewRelic::Agent::Sampler.instance_eval { @sampler_classes }
    assert(sampler_classes.include?(test_class), "Sampler classes (#{@sampler_classes.inspect}) does not include #{test_class.inspect}")
    # cleanup the sampler created above
    NewRelic::Agent::Sampler.instance_eval { @sampler_classes.delete(test_class) }
  end

  def test_sampler_classes_should_be_an_array
    sampler_classes = NewRelic::Agent::Sampler.instance_variable_get('@sampler_classes')
    assert(sampler_classes.is_a?(Array), 'Sampler classes should be saved as an array')
    assert(sampler_classes.include?(NewRelic::Agent::Samplers::CpuSampler), 'Sampler classes should include the CPU sampler')
  end

  def test_enabled_should_return_true_if_name_unknown
    assert UnnamedSampler.enabled?
  end

  def test_initialize_should_accept_id_argument
    UnnamedSampler.new(:larry)
  end

  def test_initialize_should_work_without_id_argument
    UnnamedSampler.new
  end

  def test_initialize_should_set_id_from_passed_id
    sampler = DummySampler.new(:larry)
    assert_equal(:larry, sampler.id)
  end

  def test_initialize_should_set_id_from_name_if_no_passed_id
    sampler = DummySampler.new
    assert_equal(:dummy, sampler.id)
  end

  def test_enabled_should_return_false_if_disabled_via_config_setting
    with_config(:disable_dummy_sampler => true) do
      refute DummySampler.enabled?
    end
  end

  def test_enabled_should_return_true_if_enabled_via_config_setting
    with_config(:disable_dummy_sampler => false) do
      assert DummySampler.enabled?
    end
  end
end
