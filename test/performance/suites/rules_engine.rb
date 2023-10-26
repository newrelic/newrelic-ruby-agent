# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class RulesEngineTests < Performance::TestCase
  ITERATIONS = 150_000

  def setup
    @basic_rule_specs = {
      "transaction_segment_terms": [
        {
          "prefix": 'WebTransaction/Custom',
          "terms": %w[one two three]
        },
        {
          "prefix": 'WebTransaction/Uri',
          "terms": %w[seven eight nine]
        }
      ]
    }
  end

  def test_rules_engine_init_transaction_rules
    measure(ITERATIONS) do
      NewRelic::Agent::RulesEngine.create_transaction_rules(@basic_rule_specs)
    end
  end

  def test_rules_engine_rename_transaction_rules
    measure(ITERATIONS) do
      rules_engine = NewRelic::Agent::RulesEngine.create_transaction_rules(@basic_rule_specs)
      rules_engine.rename('WebTransaction/Uri/one/two/seven/user/nine/account')
      rules_engine.rename('WebTransaction/Custom/one/two/seven/user/nine/account')
      rules_engine.rename('WebTransaction/Other/one/two/foo/bar')
    end
  end
end
