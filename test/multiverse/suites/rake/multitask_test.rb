# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'rake_test_helper'

if NewRelic::Agent::Instrumentation::Rake.should_install?
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
          "Rake/execute/multitask",
          "Rake/execute/named:before",
          "Rake/execute/named:during",
          "Rake/execute/named:after"
      end
    end

    def test_generate_transaction_trace_with_multitask
      with_tasks_traced("named:all") do
        run_rake("named:all --multitask")

        expected_nodes = ["ROOT",
          "OtherTransaction/Rake/invoke/named:all",
          "Rake/execute/multitask",
          "Rake/execute/named:before",
          "custom_before",
          "Rake/execute/named:during",
          "custom_during",
          "Rake/execute/named:after",
          "custom_after"]

        actual_nodes = single_transaction_trace_posted.tree.nodes.flatten
        # check to make sure all expected nodes are inside of actual
        assert_empty expected_nodes - actual_nodes
      end
    end
  end
end
