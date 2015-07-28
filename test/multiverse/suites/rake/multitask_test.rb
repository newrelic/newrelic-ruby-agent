# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(__FILE__, '..', 'rake_test_helper'))

if ::NewRelic::Agent::Instrumentation::RakeInstrumentation.should_install?
class MultiTaskTest < Minitest::Test
  include MultiverseHelpers
  include RakeTestHelper

  setup_and_teardown_agent

  def test_generate_scoped_metrics_for_children_if_always_multitask_set
    with_tasks_traced("named:all") do
      run_rake("named:all --multitask")

      assert_metric_names_posted "OtherTransaction/Rake/invoke/named:all",
                                 "OtherTransaction/Rake/all",
                                 "OtherTransaction/all",
                                 "Rake/execute/multitask"

      refute_metric_names_posted "Rake/execute/named:before",
                                 "Rake/execute/named:during",
                                 "Rake/execute/named:after"
    end
  end

  def test_generate_transaction_trace_with_placeholder_node
    with_tasks_traced("named:all") do
      run_rake("named:all --multitask")

      expected = [{},
                   [{},
                     [{"statement"=>"Couldn't trace concurrent prereq tasks: named:before, named:during, named:after"}]]]
      assert_equal expected, single_transaction_trace_posted.tree.node_params
    end
  end
end
end
