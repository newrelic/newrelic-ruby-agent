# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

class SegmentTermsRuleTests < Performance::TestCase
  def setup

  end

  def test_segment_terms_rule_matches?
    measure do
      NewRelic::Agent::RulesEngine::SegmentTermsRule.new({
        'prefix' => 'foo/bar/',
        'terms'  => []
      }).matches?('foo/bar')
    end
  end

  def test_segment_terms_rule_apply
    measure do
      NewRelic::Agent::RulesEngine::SegmentTermsRule.new({
        'prefix' => 'foo/bar/',
        'terms'  => []
      }).apply('foo/bar/baz/qux')
    end
  end
end
