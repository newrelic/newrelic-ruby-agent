# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

# RUBY-839 make sure there is no STDOUT chatter
require 'open3'

class StartUpTest < Minitest::Test
  GIT_NOISE = "fatal: Not a git repository (or any of the parent directories): .git\n"
  JRUBY_9000_NOISE = [
    /uri\:classloader\:\/jruby\/kernel\/kernel\.rb\:\d*\: warning: unsupported exec option: close_others/, # https://github.com/jruby/jruby/issues/1913
    /.*\/lib\/ruby\/stdlib\/jar_dependencies.rb:\d*: warning: shadowing outer local variable - (group_id|artifact_id)/, # https://github.com/mkristian/jar-dependencies/commit/65c71261b1522f7b10fcb95de42ea4799de3a83a
    /.*warning\: too many arguments for format string/ # Fixed in 9.1.3.0, see https://github.com/jruby/jruby/issues/3934
  ]
  BUNDLER_NOISE = [
    %r{.*gems/bundler-1.12.5/lib/bundler/rubygems_integration.rb:468: warning: method redefined; discarding old find_spec_for_exe},
    %r{.*lib/ruby/site_ruby/2.3.0/rubygems.rb:261: warning: previous definition of find_spec_for_exe was here}
  ]
  NET_HTTP_NOISE = [
    %r{((.*ruby-2\.[1-2]\.\d+)|(/opt/hostedtoolcache/Ruby/2.2.10/x64))/lib/ruby/2\.[1-2]\.\d+/net/http\.rb:895: warning: instance variable @npn_protocols not initialized},
    %r{((.*ruby-2\.[1-2]\.\d+)|(/opt/hostedtoolcache/Ruby/2.2.10/x64))/lib/ruby/2\.[1-2]\.\d+/net/http\.rb:895: warning: instance variable @npn_select_cb not initialized}
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
      /Exception\: java\.lang.*\n/
    ]

    expected_noise << JRUBY_9000_NOISE if jruby_9000

    expected_noise.flatten.each { |noise| output.gsub!(noise, "") }

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

    assert_equal(['my great app'], NewRelic::Agent.config[:app_name])
  end

  def test_agent_does_not_start_if_hsm_and_lasp_both_enabled
    ruby = <<RUBY
require "new_relic/agent"
NewRelic::Agent.manual_start(security_policies_token: "ffff-ffff-ffff-ffff",
                             high_security: true,
                             log_file_path: "STDOUT")
RUBY
    cmd = "bundle exec ruby -e '#{ruby}'"

    _, sout, serr = Open3.popen3(cmd)
    output = sout.read + serr.read

    assert_match /ERROR.*Security Policies and High Security Mode cannot both be present/, output, output
  end

  if RUBY_PLATFORM != 'java'
    def test_after_fork_clears_existing_transactions
      with_config clear_transaction_state_after_fork: true do
        read, write = IO.pipe

        NewRelic::Agent.manual_start(:app_name => 'my great app')

        in_transaction "outer txn" do
          pid = Process.fork do
            read.close
            NewRelic::Agent.after_fork

            txn = NewRelic::Agent::Tracer.current_transaction
            txn_name = txn ? txn.best_name : nil
            Marshal.dump(txn_name, write)
          end
          write.close
          result = read.read
          Process.wait(pid)

          inner_txn_name = Marshal.load(result)

          refute inner_txn_name
        end
      end
    end
  end

  def test_no_warnings
    with_environment('NEW_RELIC_TRANSACTION_TRACER_TRANSACTION_THRESHOLD' => '-10',
      'NEW_RELIC_PORT' => $collector.port.to_s) do
      output = `bundle exec ruby -w script/warnings.rb 2>&1`
      expected_noise = [GIT_NOISE, NET_HTTP_NOISE]

      expected_noise << JRUBY_9000_NOISE if jruby_9000
      expected_noise << BUNDLER_NOISE if bundler_rubygem_conflicts?

      expected_noise.flatten.each { |noise| output.gsub!(noise, "") }
      output.strip!

      assert_equal NewRelic::VERSION::STRING, output
    end
  end

  def assert_runs_without_errors(command)
    output = `#{command}`
    assert_equal 0, $?.exitstatus

    problems = output.scan(/ERROR : .*/)
    assert_empty problems
  end

  def jruby_9000
    defined?(JRUBY_VERSION) && Gem::Version.new(JRUBY_VERSION) >= Gem::Version.new("9.0.0")
  end

  def bundler_rubygem_conflicts?
    Gem::Version.new(Gem::VERSION) == Gem::Version.new("2.6.6") and
      Gem::Version.new(Bundler::VERSION) == Gem::Version.new("1.12.5")
  end
end
