# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))

class RulesEngineTest < Minitest::Test
  def test_rule_defaults
    rule = create_rule('match_expression' => '.*',
                       'replacement'      => '*')
    assert !rule.terminate_chain
    assert !rule.each_segment
    assert !rule.ignore
    assert !rule.replace_all
    assert_equal 0, rule.eval_order
  end

  def test_rule_applies_regex_rename
    rule = create_rule('match_expression' => '[0-9]+',
                       'replacement'      => '*')

    input = 'foo/1/bar/22'

    refute(rule.terminal?)
    assert(rule.matches?(input))
    assert_equal('foo/*/bar/22', rule.apply(input))
  end

  def test_rules_can_apply_to_frozen_strings
    rule = create_rule('match_expression' => '[0-9]+',
                       'replacement'      => '*')

    input = 'foo/1/bar/22'.freeze

    refute(rule.terminal?)
    assert(rule.matches?(input))
    assert_equal('foo/*/bar/22', rule.apply('foo/1/bar/22'.freeze))
  end

  def test_rule_applies_grouping_with_replacements
    rule = create_rule('match_expression' => '([0-9]+)',
                       'replacement'      => '\\1\\1')

    input = 'foo/1/bar/22'

    refute(rule.terminal?)
    assert(rule.matches?(input))
    assert_equal('foo/11/bar/22', rule.apply('foo/1/bar/22'))
  end

  def test_rule_renames_all_matches_when_replace_all_is_true
    rule = create_rule('match_expression' => '[0-9]+',
                       'replacement'      => '*',
                       'replace_all'      => true)

    refute(rule.terminal?)
    assert(rule.matches?('foo/1/bar/22'))
    assert_equal('foo/*/bar/*', rule.apply('foo/1/bar/22'))
  end

  def test_rule_with_no_match
    rule = create_rule('match_expression' => 'QQ',
                       'replacement'      => 'qq')

    refute(rule.terminal?)
    refute(rule.matches?('foo/1/bar/22'))
    assert_equal('foo/1/bar/22', rule.apply('foo/1/bar/22'))
  end

  def test_applies_rules_in_order
    rule = create_rule('match_expression' => '[0-9]+',
                       'replacement'      => '*',
                       'replace_all'      => true,
                       'eval_order'       => 0)

    rerule = create_rule('match_expression' => '\*',
                         'replacement'      => 'x',
                         'replace_all'      => true,
                         'eval_order'       => 1)

    engine = NewRelic::Agent::RulesEngine.new([rerule, rule])

    assert_equal('foo/x/bar/x', engine.rename('foo/1/bar/22'))
  end

  def test_can_apply_rules_to_all_segments
    rule = create_rule('match_expression' => '[0-9]+.*',
                       'replacement'      => '*',
                       'each_segment'     => true)

    engine = NewRelic::Agent::RulesEngine.new([rule])

    assert_equal('foo/*/bar/*', engine.rename('foo/1a/bar/22b'))
  end

  def test_stops_after_terminate_chain
    rule0 = create_rule('match_expression' => '[0-9]+',
                        'replacement'      => '*',
                        'each_segment'     => true,
                        'eval_order'       => 0,
                        'terminate_chain'  => true)

    rule1 = create_rule('match_expression' => '.*',
                        'replacement'      => 'X',
                        'replace_all'      => true,
                        'eval_order'       => 1)

    engine = NewRelic::Agent::RulesEngine.new([rule0, rule1])

    assert_equal('foo/*/bar/*', engine.rename('foo/1/bar/22'))
  end

  def create_rule(spec)
    NewRelic::Agent::RulesEngine::ReplacementRule.new(spec)
  end

  load_cross_agent_test('rules').each do |testcase|
    define_method("test_#{testcase['testname']}") do
      engine = NewRelic::Agent::RulesEngine.create_metric_rules('metric_name_rules' => testcase['rules'])

      testcase["tests"].each do |test|
        assert_equal(test["expected"], engine.rename(test["input"]), "Input: #{test['input'].inspect}")
      end
    end
  end

  load_cross_agent_test('transaction_segment_terms').each do |testcase|
    define_method("test_app_segment_terms_#{testcase['testname']}") do
      engine = NewRelic::Agent::RulesEngine.create_transaction_rules(testcase)
      testcase['tests'].each do |test|
        assert_equal(test["expected"], engine.rename(test["input"]), "Input: #{test['input'].inspect}")
      end
    end
  end

end
