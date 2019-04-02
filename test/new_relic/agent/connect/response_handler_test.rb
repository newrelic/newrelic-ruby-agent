# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..', '..', '..','test_helper'))
require 'new_relic/agent/agent'

class NewRelic::Agent::Agent::ResponseHandlerTest < Minitest::Test

  def setup
    server = NewRelic::Control::Server.new('localhost', 30303)
    @service = NewRelic::Agent::NewRelicService.new('abcdef', server)
    NewRelic::Agent.instance.service = @service
    @local_host = nil

    NewRelic::Agent.reset_config
    @agent = NewRelic::Agent.instance
    @config = NewRelic::Agent.config
    @response_handler = NewRelic::Agent::Connect::ResponseHandler.new(@agent, @config)
  end

  def test_configure_agent_replaces_server_config
    @response_handler.configure_agent('apdex_t' => 42)
    assert_equal 42, @config[:apdex_t]
    assert_kind_of NewRelic::Agent::Configuration::ServerSource, @config.source(:apdex_t)

    # this should create a new server source that replaces the existing one that
    # had apdex_t specified, rather than layering on top of the existing one.
    @response_handler.configure_agent('data_report_period' => 12)
    assert_kind_of NewRelic::Agent::Configuration::DefaultSource, @config.source(:apdex_t)
  end

  def test_configure_agent
    config = {
      'agent_run_id' => 'fishsticks',
      'collect_traces' => true,
      'collect_errors' => true,
      'sample_rate' => 10,
      'agent_config' => { 'transaction_tracer.record_sql' => 'raw' }
    }
    
    with_config(:'transaction_tracer.enabled' => true) do
      @response_handler.configure_agent(config)
      assert_equal 'fishsticks', @agent.service.agent_id
      assert_equal 'raw', @config[:'transaction_tracer.record_sql']
    end
  end

  def test_configure_agent_without_config
    @agent.service.agent_id = 'blah'
    @response_handler.configure_agent(nil)
    assert_equal 'blah', @agent.service.agent_id
  end

  def test_configure_agent_saves_transaction_name_rules
    @agent.instance_variable_set(:@transaction_rules,
                                            NewRelic::Agent::RulesEngine.new)
    config = {
      'transaction_name_rules' => [ { 'match_expression' => '88',
                                      'replacement'      => '**' },
                                    { 'match_expression' => 'xx',
                                      'replacement'      => 'XX' } ]
    }
    @response_handler.configure_agent(config)

    rules = @agent.transaction_rules
    assert_equal 2, rules.size
    assert(rules.find{|r| r.match_expression == /88/i && r.replacement == '**' },
           "rule not found among #{rules}")
    assert(rules.find{|r| r.match_expression == /xx/i && r.replacement == 'XX' },
           "rule not found among #{rules}")
  ensure
    @agent.instance_variable_set(:@transaction_rules,
                                            NewRelic::Agent::RulesEngine.new)
  end


  def test_configure_agent_saves_metric_name_rules
    @agent.instance_variable_set(:@metric_rules,
                                            NewRelic::Agent::RulesEngine.new)
    config = {
      'metric_name_rules' => [ { 'match_expression' => '77',
                                 'replacement'      => '&&' },
                               { 'match_expression' => 'yy',
                                 'replacement'      => 'YY' }]
    }
    @response_handler.configure_agent(config)

    rules = @agent.stats_engine.metric_rules
    assert_equal 2, rules.size
    assert(rules.find{|r| r.match_expression == /77/i && r.replacement == '&&' },
           "rule not found among #{rules}")
    assert(rules.find{|r| r.match_expression == /yy/i && r.replacement == 'YY' },
           "rule not found among #{rules}")
  ensure
    @agent.instance_variable_set(:@metric_rules,
                                            NewRelic::Agent::RulesEngine.new)
  end

  def test_sql_tracer_disabled_when_tt_disabled_by_server
    with_config_low_priority({
                 :'slow_sql.enabled'           => true,
                 :'transaction_tracer.enabled' => true,
                 :monitor_mode                 => true}) do
      @response_handler.configure_agent('collect_traces' => false)

      refute @agent.sql_sampler.enabled?, 'sql enabled when tracing disabled by server'
    end
  end
end