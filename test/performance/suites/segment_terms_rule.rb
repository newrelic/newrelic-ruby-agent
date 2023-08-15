# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class SegmentTermsRuleTests < Performance::TestCase
  ITERATIONS = 600_000

  def setup; end

  def test_segment_terms_rule_matches?
    measure(ITERATIONS) do
      NewRelic::Agent::RulesEngine::SegmentTermsRule.new({
        'prefix' => 'foo/bar/',
        'terms' => []
      }).matches?('foo/bar')
    end
  end

  def test_segment_terms_rule_apply
    measure(ITERATIONS) do
      NewRelic::Agent::RulesEngine::SegmentTermsRule.new({
        'prefix' => 'foo/bar/',
        'terms' => []
      }).apply('foo/bar/baz/qux')
    end
  end
end
