# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'test/unit'
ENV['NEWRELIC_GEM_PATH'] = '../../../../../ruby_agent'

class MultiverseTest < Test::Unit::TestCase
  RUNNER = File.expand_path(File.join(
    File.dirname(__FILE__), '..', 'script', 'runner'))
  TEST_SUITE_EXAMPLES_ROOT = File.expand_path(File.join(
    File.dirname(__FILE__), 'suite_examples'))

  # encapsulates state from a example test suite run
  class SuiteRun
    def initialize
      @output = ''
    end
    attr_accessor :output, :exit_status
  end

  def suite_directory_for(name)
    File.join(TEST_SUITE_EXAMPLES_ROOT, name.to_s)
  end

  def run_suite(suite)
    ENV['SUITES_DIRECTORY'] = suite_directory_for(suite)
    ENV['NEWRELIC_GEM_PATH'] = '../../../../../../..'
    cmd = RUNNER
    suite_run = SuiteRun.new
    IO.popen(cmd) do |io|
      while line = io.gets
        suite_run.output << line
        # print line # uncomment for debugging rake test:self
      end
    end
    suite_run.exit_status = $?
    suite_run
  end

  def test_suite_environments_are_isolated_from_each_other
    run = run_suite('one')
    assert_equal 0, run.exit_status, "Test suite should demonstrate that " <<
                                     "gems loaded in for one suite don't " <<
                                     "persist in the next suite\n"# + run.output
  end

  def test_failed_tests_mean_unsuccessful_exit_code_in_parent_with_fork_execute_mode
    run = run_suite('two')
    refute_equal 0, run.exit_status, "Failed test should mean unsucessful " <<
                                         "exit status in parent \n" # + run.output
  end

  def test_failed_tests_mean_unsucessful_exit_code_in_parent_with_spawn_execute_mode
    run = run_suite('three')
    refute_equal 0, run.exit_status, "Failed test in spawn mode should mean unsucessful " <<
                                         "exit status in parent \n" # + run.output
  end
end
