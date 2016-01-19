# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class RulesEngineTests < Performance::TestCase
  def setup
    @basic_rule_specs = {
      "transaction_segment_terms": [
        {
          "prefix": "WebTransaction/Custom",
          "terms": ["one", "two", "three"]
        },
        {
          "prefix": "WebTransaction/Uri",
          "terms": ["seven", "eight", "nine"]
        }
      ]
    }
  end

  def test_rules_engine_init_transaction_rules
    measure do
      NewRelic::Agent::RulesEngine.create_transaction_rules(@basic_rule_specs)
    end
  end

  def test_rules_engine_rename_transaction_rules
    measure do
      rules_engine = NewRelic::Agent::RulesEngine.create_transaction_rules(@basic_rule_specs)
      rules_engine.rename "WebTransaction/Uri/one/two/seven/user/nine/account"
      rules_engine.rename "WebTransaction/Custom/one/two/seven/user/nine/account"
      rules_engine.rename "WebTransaction/Other/one/two/foo/bar"
    end
  end
end
