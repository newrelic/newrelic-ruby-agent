# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))

class RulesEngineTest < Test::Unit::TestCase
  def setup
    @engine = NewRelic::Agent::RulesEngine.new
  end

  def test_rule_defaults
    rule = NewRelic::Agent::RulesEngine::Rule.new('match_expression' => '.*',
                                                  'replacement'      => '*')
    assert !rule.terminate_chain
    assert !rule.each_segment
    assert !rule.ignore
    assert !rule.replace_all
    assert_equal 0, rule.eval_order
  end

  def test_rule_applies_regex_rename
    rule = NewRelic::Agent::RulesEngine::Rule.new('match_expression' => '[0-9]+',
                                                  'replacement'      => '*')
    assert_equal(['foo/*/bar/22', true], rule.apply('foo/1/bar/22'))
  end

  def test_rules_can_apply_to_frozen_strings
    rule = NewRelic::Agent::RulesEngine::Rule.new('match_expression' => '[0-9]+',
                                                  'replacement'      => '*')
    assert_equal(['foo/*/bar/22', true], rule.apply('foo/1/bar/22'.freeze))
  end

  def test_rule_applies_grouping_with_replacements
    rule = NewRelic::Agent::RulesEngine::Rule.new('match_expression' => '([0-9]+)',
                                                  'replacement'      => '\\1\\1')
    assert_equal(['foo/11/bar/22', true], rule.apply('foo/1/bar/22'))
  end

  def test_rule_renames_all_matches_when_replace_all_is_true
    rule = NewRelic::Agent::RulesEngine::Rule.new('match_expression' => '[0-9]+',
                                                  'replacement'      => '*',
                                                  'replace_all'      => true)
    assert_equal(['foo/*/bar/*', true], rule.apply('foo/1/bar/22'))
  end

  def test_rule_with_no_match
    rule = NewRelic::Agent::RulesEngine::Rule.new('match_expression' => 'QQ',
                                                  'replacement'      => 'qq')
    assert_equal(['foo/1/bar/22', false], rule.apply('foo/1/bar/22'))
  end

  def test_applies_rules_in_order
    rule = NewRelic::Agent::RulesEngine::Rule.new('match_expression' => '[0-9]+',
                                                  'replacement'      => '*',
                                                  'replace_all'      => true,
                                                  'eval_order'       => 0)
    rerule = NewRelic::Agent::RulesEngine::Rule.new('match_expression' => '\*',
                                                    'replacement'      => 'x',
                                                    'replace_all'      => true,
                                                    'eval_order'       => 1)
    @engine << rerule
    @engine << rule

    assert_equal('foo/x/bar/x', @engine.rename('foo/1/bar/22'))
  end

  def test_can_apply_rules_to_all_segments
    rule = NewRelic::Agent::RulesEngine::Rule.new('match_expression' => '[0-9]+.*',
                                                  'replacement'      => '*',
                                                  'each_segment'     => true)
    @engine << rule

    assert_equal('foo/*/bar/*', @engine.rename('foo/1a/bar/22b'))
  end

  def test_stops_after_terminate_chain
    rule0 = NewRelic::Agent::RulesEngine::Rule.new('match_expression' => '[0-9]+',
                                                   'replacement'      => '*',
                                                   'each_segment'     => true,
                                                   'eval_order'       => 0,
                                                   'terminate_chain'  => true)
    rule1 = NewRelic::Agent::RulesEngine::Rule.new('match_expression' => '.*',
                                                   'replacement'      => 'X',
                                                   'replace_all'      => true,
                                                   'eval_order'       => 1)
    @engine << rule0
    @engine << rule1

    assert_equal('foo/*/bar/*', @engine.rename('foo/1/bar/22'))
  end
end
