ENV['SKIP_RAILS'] = 'true'
require File.expand_path('../../../test_helper', __FILE__)

class NewRelic::Agent::RpmAgentTest < Test::Unit::TestCase # ActiveSupport::TestCase
  extend TestContexts

  attr_reader :agent

  with_running_agent do
    # Fake out the agent to think mongrel is running

    should "agent_setup" do
      assert NewRelic::Agent.instance.class == NewRelic::Agent::Agent
      assert_raise RuntimeError do
        NewRelic::Control.instance.init_plugin :agent_enabled => false
      end
    end

    should "public_apis" do
      assert_raise RuntimeError do
        NewRelic::Agent.set_sql_obfuscator(:unknown) do |sql|
          puts sql
        end
      end

      ignore_called = false
      NewRelic::Agent.ignore_error_filter do |e|
        ignore_called = true
        nil
      end
      NewRelic::Agent.notice_error(StandardError.new("message"), :request_params => {:x => "y"})
      assert ignore_called
      NewRelic::Agent.instance.error_collector.instance_variable_set '@ignore_filter', nil
    end

    should "startup_shutdown" do
      with_config(:agent_enabled => true) do
        @agent = NewRelic::Agent::ShimAgent.instance
        @agent.shutdown
        assert (not @agent.started?)
        @agent.start
        assert !@agent.started?
        # this installs the real agent:
        NewRelic::Agent.manual_start
        @agent = NewRelic::Agent.instance
        assert @agent != NewRelic::Agent::ShimAgent.instance
        assert @agent.started?
        @agent.shutdown
        assert !@agent.started?
        @agent.start
        assert @agent.started?
        NewRelic::Agent.shutdown
      end
    end

    should "manual_start" do
      NewRelic::Agent.instance.expects(:connect).once
      NewRelic::Agent.instance.expects(:start_worker_thread).once
      NewRelic::Agent.instance.instance_variable_set '@started', nil
      NewRelic::Agent.manual_start :monitor_mode => true, :license_key => ('x' * 40)
      NewRelic::Agent.shutdown
    end

    should "post_fork_handler" do
      NewRelic::Agent.manual_start :monitor_mode => true, :license_key => ('x' * 40)
      NewRelic::Agent.after_fork
      NewRelic::Agent.after_fork
      NewRelic::Agent.shutdown
    end
    should "manual_overrides" do
      NewRelic::Agent.manual_start :app_name => "testjobs", :dispatcher_instance_id => "mailer"
      assert_equal "testjobs", NewRelic::Agent.config.app_names[0]
      assert_equal "mailer", NewRelic::Control.instance.local_env.dispatcher_instance_id
      NewRelic::Agent.shutdown
    end

    should "restart" do
      NewRelic::Agent.manual_start :app_name => "noapp", :dispatcher_instance_id => ""
      NewRelic::Agent.manual_start :app_name => "testjobs", :dispatcher_instance_id => "mailer"
      assert_equal "testjobs", NewRelic::Agent.config.app_names[0]
      assert_equal "mailer", NewRelic::Control.instance.local_env.dispatcher_instance_id
      NewRelic::Agent.shutdown
    end

    should "send_timeslice_data" do
      # this test fails due to a rubinius bug
      return if NewRelic::LanguageSupport.using_engine?('rbx')
      @agent.service = NewRelic::FakeService.new
      @agent.service.expects(:metric_data).returns([ [{'name' => '/A/b/c'}, 1],
                                                     [{'name' => '/A/b/c', 'scope' => '/X'}, 2],
                                                     [{'name' => '/A/b/d'}, 3] ])
      @agent.send :harvest_and_send_timeslice_data
      assert_equal 3, @agent.metric_ids.size
      assert_equal(3, @agent.metric_ids[NewRelic::MetricSpec.new('/A/b/d')],
                   @agent.metric_ids.inspect)
    end
    should "set_record_sql" do
      @agent.set_record_sql(false)
      assert !NewRelic::Agent.is_sql_recorded?
      NewRelic::Agent.disable_sql_recording do
        assert_equal false, NewRelic::Agent.is_sql_recorded?
        NewRelic::Agent.disable_sql_recording do
          assert_equal false, NewRelic::Agent.is_sql_recorded?
        end
        assert_equal false, NewRelic::Agent.is_sql_recorded?
      end
      assert !NewRelic::Agent.is_sql_recorded?
      @agent.set_record_sql(nil)
    end

    should "version" do
      assert_match /\d\.\d+\.\d+/, NewRelic::VERSION::STRING
    end

    context "with transaction api" do
      should "reject empty arguments" do
        assert_raises RuntimeError do
          NewRelic::Agent.record_transaction 0.5
        end
      end
      should "record a transaction" do
        NewRelic::Agent.record_transaction 0.5, 'uri' => "/users/create?foo=bar"
      end
    end
  end
end
