# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../test_helper'
require 'new_relic/agent/autostart'

class AutostartTest < Minitest::Test
  def test_typically_the_agent_should_autostart
    assert_predicate ::NewRelic::Agent::Autostart, :agent_should_start?
  end

  def test_agent_will_not_autostart_in_certain_contexts_recognized_by_constants_being_defined
    rails_is_present = defined?(::Rails)
    NewRelic::Agent.config[:'autostart.denylisted_constants'].split(/\s*,\s*/).each do |constant|
      assert_predicate ::NewRelic::Agent::Autostart, :agent_should_start?, 'Agent should autostart by default'

      # For Rails::Command::ConsoleCommand as an example, eval these:
      #   'module ::Rails; end',
      #   'module ::Rails::Command; end', and
      #   'module ::Rails::Command::ConsoleCommand; end'
      #
      # If this test is running within a context that already has Rails defined,
      # the result of `::NewRelic::LanguageSupport.constantize('::Rails')` will
      # be non-nil and the first `eval` will be skipped.
      elements = constant.split('::')
      elements.inject(+'') do |namespace, element|
        namespace += "::#{element}"
        eval("module #{namespace}; end") unless ::NewRelic::LanguageSupport.constantize(namespace)
        namespace
      end

      refute_predicate ::NewRelic::Agent::Autostart,
        :agent_should_start?,
        "Agent shouldn't autostart when the '#{constant}' constant is defined"

      # For Rails::Command::ConsoleCommand as an example, eval these:
      # "::Rails::Command.send(:remove_const, 'ConsoleCommand'.to_sym)" and
      # "::Rails.send(:remove_const, 'Command'.to_sym)".
      #
      # and then invoke `Object.send(:remove_const, 'Rails'.to_sym)` to
      # undefine Rails itself. If Rails was already defined before this test
      # ran, don't invoke the `Object.send` command and leave Rails alone.
      dupe = constant.dup
      while dupe =~ /^.+(::.+)$/
        element = Regexp.last_match(1)
        dupe.sub!(/#{element}$/, '')
        eval("::#{dupe}.send(:remove_const, '#{element.sub('::', '')}'.to_sym)")
      end
      Object.send(:remove_const, dupe.to_sym) unless dupe == 'Rails' && rails_is_present
    end
  end

  def test_agent_will_autostart_if_global_CONSOLE_constant_is_defined
    Object.const_set(:Console, Class.new)

    assert_predicate ::NewRelic::Agent::Autostart, :agent_should_start?, "Agent shouldn't find ::Console"
  ensure
    Object.send(:remove_const, :Console)
  end

  def test_agent_wont_start_if_dollar_0_is_irb
    @orig_dollar_0, $0 = $0, '/foo/bar/irb'

    refute_predicate ::NewRelic::Agent::Autostart, :agent_should_start?, "Agent shouldn't autostart when process is invoked by irb"
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

      refute_predicate ::NewRelic::Agent::Autostart, :agent_should_start?, "Agent shouldn't start during #{task.inspect} rake task"
    end
  end

  MY_CONST = true
  def test_denylisted_constants_can_be_configured
    with_config('autostart.denylisted_constants' => 'IRB,::AutostartTest::MY_CONST') do
      refute_predicate ::NewRelic::Agent::Autostart, :agent_should_start?, "Agent shouldn't autostart when environment contains denylisted constant"
    end
  end

  def test_denylisted_executable_can_be_configured
    @orig_dollar_0, $0 = $0, '/foo/bar/baz'

    with_config('autostart.denylisted_executables' => 'boo,baz') do
      refute_predicate ::NewRelic::Agent::Autostart, :agent_should_start?, "Agent shouldn't autostart when process is invoked by denylisted executable"
    end
  ensure
    $0 = @orig_dollar_0
  end

  def test_denylisted_rake_tasks_can_be_configured
    with_config('autostart.denylisted_rake_tasks' => 'foo,bar,baz:bang') do
      Rake.stubs(:application => stub(:top_level_tasks => ['biz', 'baz:bang']))

      refute_predicate ::NewRelic::Agent::Autostart, :agent_should_start?, "Agent shouldn't during denylisted rake task"
    end
  end
end
