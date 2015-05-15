# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# RUBY-839 make sure there is no STDOUT chatter
require 'open3'

class StartUpTest < Minitest::Test
  GIT_NOISE = "fatal: Not a git repository (or any of the parent directories): .git\n"

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

    expected_noise.each {|noise| output.gsub!(noise, "")}

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
      output = `bundle exec ruby -w -r bundler/setup -r newrelic_rpm -e 'puts NewRelic::VERSION::STRING' 2>&1`
      output.gsub!(GIT_NOISE, "")
      output.chomp!

      assert_equal NewRelic::VERSION::STRING, output
    end
  end

  def assert_runs_without_errors(command)
    output = `#{command}`
    assert_equal 0, $?.exitstatus

    problems = output.scan(/ERROR : .*/)
    assert_empty problems
  end
end
