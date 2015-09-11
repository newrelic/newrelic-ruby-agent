# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# RUBY-839 make sure there is no STDOUT chatter
require 'open3'

class StartUpTest < Minitest::Test
  GIT_NOISE = "fatal: Not a git repository (or any of the parent directories): .git\n"
  JRUBY_9000_NOISE = [
    /uri\:classloader\:\/jruby\/kernel\/kernel\.rb\:\d*\: warning: unsupported exec option: close_others/, # https://github.com/jruby/jruby/issues/1913
    /.*\/lib\/ruby\/stdlib\/jar_dependencies.rb:\d*: warning: shadowing outer local variable - (group_id|artifact_id)/, #https://github.com/mkristian/jar-dependencies/commit/65c71261b1522f7b10fcb95de42ea4799de3a83a
  ]

  include MultiverseHelpers

  setup_and_teardown_agent

  def test_should_not_print_to_stdout_when_logging_available
    ruby = 'require "newrelic_rpm"; NewRelic::Agent.manual_start; NewRelic::Agent.shutdown'
    cmd = "bundle exec ruby -e '#{ruby}'"

    _sin, sout, serr = Open3.popen3(cmd)
    output = sout.read + serr.read

    expected_noise = [
      "JRuby limited openssl loaded. http://jruby.org/openssl\n",
      "gem install jruby-openssl for full support.\n",
      GIT_NOISE,
      /Exception\: java\.lang.*\n/]

    expected_noise << JRUBY_9000_NOISE if jruby_9000

    expected_noise.flatten.each {|noise| output.gsub!(noise, "")}

    assert_equal '', output.chomp
  end

  def test_instrumentation_loads_clean_even_without_dependencies
    assert_runs_without_errors("bundle exec ruby script/loading.rb")
  end

  def test_manual_start_with_symbol_for_environment
    assert_runs_without_errors("bundle exec ruby script/symbol_env.rb")
  end

  def test_can_call_public_api_methods_when_agent_disabled
    assert_runs_without_errors("bundle exec ruby script/public_api_when_disabled.rb")
  end

  def test_manual_start_logs_about_mismatched_environment
    output = `bundle exec ruby script/env_change.rb`

    assert_match(/ERROR.*Attempted to start agent.*production.*development/, output, output)
  end

  def test_after_fork_does_not_blow_away_manual_start_settings
    NewRelic::Agent.manual_start(:app_name => 'my great app')

    NewRelic::Agent.after_fork

    assert_equal('my great app', NewRelic::Agent.config[:app_name])
  end

  # Older rubies have a lot of warnings that we don't care much about. Track it
  # going forward from Ruby 2.1.
  if RUBY_VERSION >= "2.1"
    def test_no_warnings
      with_environment('NEW_RELIC_TRANSACTION_TRACER_TRANSACTION_THRESHOLD' => '-10',
                       'NEW_RELIC_PORT' => $collector.port.to_s) do

        output = `bundle exec ruby -w script/warnings.rb 2>&1`
        expected_noise = [GIT_NOISE]

        expected_noise << JRUBY_9000_NOISE if jruby_9000

        expected_noise.flatten.each {|noise| output.gsub!(noise, "")}
        output.strip!

        assert_equal NewRelic::VERSION::STRING, output
      end
    end
  end

  def assert_runs_without_errors(command)
    output = `#{command}`
    assert_equal 0, $?.exitstatus

    problems = output.scan(/ERROR : .*/)
    assert_empty problems
  end

  def jruby_9000
    defined?(JRUBY_VERSION) && NewRelic::VersionNumber.new(JRUBY_VERSION) >= "9.0.0"
  end
end
