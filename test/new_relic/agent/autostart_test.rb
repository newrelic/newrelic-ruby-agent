# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../test_helper'
require 'new_relic/agent/autostart'

class AutostartTest < Minitest::Test
  def test_typically_the_agent_should_autostart
    assert_predicate ::NewRelic::Agent::Autostart, :agent_should_start?
  end

  if defined?(::Rails)
    def test_agent_wont_autostart_if_RAILS_CONSOLE_constant_is_defined
      refute defined?(::Rails::Console), "precondition: Rails::Console shouldn't be defined"
      Rails.const_set(:Console, Class.new)

      refute ::NewRelic::Agent::Autostart.agent_should_start?, "Agent shouldn't autostart in Rails Console session"
    ensure
      Rails.send(:remove_const, :Console)
    end
  else
    puts "Skipping `test_agent_wont_autostart_if_RAILS_CONSOLE_constant_is_defined` in #{__FILE__} because Rails is unavailable"
  end

  def test_agent_will_autostart_if_global_CONSOLE_constant_is_defined
    Object.const_set(:Console, Class.new)

    assert_predicate ::NewRelic::Agent::Autostart, :agent_should_start?, "Agent shouldn't find ::Console"
  ensure
    Object.send(:remove_const, :Console)
  end

  def test_agent_wont_start_if_dollar_0_is_irb
    @orig_dollar_0, $0 = $0, '/foo/bar/irb'

    refute ::NewRelic::Agent::Autostart.agent_should_start?, "Agent shouldn't autostart when process is invoked by irb"
  ensure
    $0 = @orig_dollar_0
  end

  RAILS_DEFAULT_RAKE_TASKS = %w[ about assets:clean assets:clobber
    assets:environment assets:precompile db:create db:drop db:fixtures:load
    db:migrate db:migrate:status db:rollback db:schema:cache:clear
    db:schema:cache:dump db:schema:dump db:schema:load db:seed db:setup
    db:structure:dump db:version doc:app log:clear middleware notes notes:custom
    rails:template rails:update routes secret spec spec:features spec:requests
    spec:controllers spec:helpers spec:models spec:views spec:routing
    spec:rcov stats test test:all test:all:db test:recent test:single
    test:uncommitted time:zones:all tmp:clear tmp:create ].each do |task|
    define_method("test_agent_wont_autostart_if_top_level_rake_task_is_#{task}") do
      Rake.stubs(:application => stub(:top_level_tasks => [task]))

      refute ::NewRelic::Agent::Autostart.agent_should_start?, "Agent shouldn't start during #{task.inspect} rake task"
    end
  end

  MY_CONST = true
  def test_denylisted_constants_can_be_configured
    with_config('autostart.denylisted_constants' => "IRB,::AutostartTest::MY_CONST") do
      refute ::NewRelic::Agent::Autostart.agent_should_start?, "Agent shouldn't autostart when environment contains denylisted constant"
    end
  end

  def test_denylisted_executable_can_be_configured
    @orig_dollar_0, $0 = $0, '/foo/bar/baz'

    with_config('autostart.denylisted_executables' => 'boo,baz') do
      refute ::NewRelic::Agent::Autostart.agent_should_start?, "Agent shouldn't autostart when process is invoked by denylisted executable"
    end
  ensure
    $0 = @orig_dollar_0
  end

  def test_denylisted_rake_tasks_can_be_configured
    with_config('autostart.denylisted_rake_tasks' => 'foo,bar,baz:bang') do
      Rake.stubs(:application => stub(:top_level_tasks => ['biz', 'baz:bang']))

      refute ::NewRelic::Agent::Autostart.agent_should_start?, "Agent shouldn't during denylisted rake task"
    end
  end
end
