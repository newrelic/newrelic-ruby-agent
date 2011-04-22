require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'test_helper'))
class NewRelic::Agent::SamplerTest < Test::Unit::TestCase
  require 'new_relic/agent/sampler'
  
  def test_inherited_should_append_subclasses_to_sampler_classes
    test_class = Class.new(NewRelic::Agent::Sampler)
    sampler_classes = NewRelic::Agent::Sampler.instance_eval { @sampler_classes }
    assert(sampler_classes.include?(test_class), "Sampler classes (#{@sampler_classes.inspect}) does not include #{test_class.inspect}")
    # cleanup the sampler created above
    NewRelic::Agent::Sampler.instance_eval { @sampler_classes.delete(test_class) }
  end

  def test_sampler_classes_should_be_an_array
    raise 'need to cover this instance'
  end

end
