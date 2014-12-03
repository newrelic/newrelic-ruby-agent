# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'securerandom'

class AgentAttributesTests < Performance::TestCase
  def setup
    require 'new_relic/agent/attribute_filter'
  end

  def test_empty_agent_attributes(timer)
    @filter = NewRelic::Agent::AttributeFilter.new(NewRelic::Agent.config)

    timer.measure do
      iterations.times do
        @filter.apply("alpha", NewRelic::Agent::AttributeFilter::DST_ALL)
        @filter.apply("beta", NewRelic::Agent::AttributeFilter::DST_ALL)
      end
    end
  end

  def test_with_attribute_rules(timer)
    with_config(:'attributes.include' => ['alpha'],
                :'attributes.exclude' => ['beta']) do

      @filter = NewRelic::Agent::AttributeFilter.new(NewRelic::Agent.config)

      timer.measure do
        iterations.times do
          @filter.apply("alpha", NewRelic::Agent::AttributeFilter::DST_ALL)
          @filter.apply("beta", NewRelic::Agent::AttributeFilter::DST_ALL)
        end
      end
    end
  end

  def test_with_wildcards(timer)
    with_config(:'attributes.include' => ['alpha*'],
                :'attributes.exclude' => ['beta*']) do

      @filter = NewRelic::Agent::AttributeFilter.new(NewRelic::Agent.config)

      timer.measure do
        iterations.times do
          @filter.apply("alpha", NewRelic::Agent::AttributeFilter::DST_ALL)
          @filter.apply("beta", NewRelic::Agent::AttributeFilter::DST_ALL)
        end
      end
    end
  end

  def test_with_tons_o_rules(timer)
    with_config(:'attributes.include' => 100.times.map { SecureRandom.hex },
                :'attributes.exclude' => 100.times.map { SecureRandom.hex }) do

      @filter = NewRelic::Agent::AttributeFilter.new(NewRelic::Agent.config)

      timer.measure do
        iterations.times do
          @filter.apply("alpha", NewRelic::Agent::AttributeFilter::DST_ALL)
          @filter.apply("beta", NewRelic::Agent::AttributeFilter::DST_ALL)
        end
      end
    end
  end
end
