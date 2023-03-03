# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class AgentAttributesTests < Performance::TestCase
  def setup
    require 'new_relic/agent/attribute_filter'
  end

  ALPHA = 'alpha'.freeze
  BETA = 'beta'.freeze

  def test_empty_agent_attributes
    @filter = NewRelic::Agent::AttributeFilter.new(NewRelic::Agent.config)

    measure do
      @filter.apply(ALPHA, NewRelic::Agent::AttributeFilter::DST_ALL)
      @filter.apply(BETA, NewRelic::Agent::AttributeFilter::DST_ALL)
    end
  end

  def test_with_attribute_rules
    with_config(:'attributes.include' => ['alpha'],
      :'attributes.exclude' => ['beta']) do
      @filter = NewRelic::Agent::AttributeFilter.new(NewRelic::Agent.config)

      measure do
        @filter.apply(ALPHA, NewRelic::Agent::AttributeFilter::DST_ALL)
        @filter.apply(BETA, NewRelic::Agent::AttributeFilter::DST_ALL)
      end
    end
  end

  def test_with_wildcards
    with_config(:'attributes.include' => ['alpha*'],
      :'attributes.exclude' => ['beta*']) do
      @filter = NewRelic::Agent::AttributeFilter.new(NewRelic::Agent.config)

      measure do
        @filter.apply(ALPHA, NewRelic::Agent::AttributeFilter::DST_ALL)
        @filter.apply(BETA, NewRelic::Agent::AttributeFilter::DST_ALL)
      end
    end
  end

  def test_with_tons_o_rules
    with_config(:'attributes.include' => Array.new(100) { fake_guid(32) },
      :'attributes.exclude' => Array.new(100) { fake_guid(32) }) do
      @filter = NewRelic::Agent::AttributeFilter.new(NewRelic::Agent.config)

      measure do
        @filter.apply(ALPHA, NewRelic::Agent::AttributeFilter::DST_ALL)
        @filter.apply(BETA, NewRelic::Agent::AttributeFilter::DST_ALL)
      end
    end
  end
end
