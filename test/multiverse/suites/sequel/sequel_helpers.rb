# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module SequelHelpers
  def setup
    super

    DB.extension(:new_relic_instrumentation)

    NewRelic::Agent.drop_buffered_data
  end

  def teardown
    super

    NewRelic::Agent.shutdown
  end
  #
  # Helpers
  #

  # Pattern to match the column headers of a Sqlite explain plan
  SQLITE_EXPLAIN_PLAN_COLUMNS_RE =
    %r{\|addr\s*\|opcode\s*\|p1\s*\|p2\s*\|p3\s*\|p4\s*\|p5\s*\|comment\s*\|}

  # This is particular to sqlite plans currently. To abstract it up, we'd need to
  # be able to specify a flavor (e.g., :sqlite, :postgres, :mysql, etc.)
  def assert_node_has_explain_plan(node, msg = nil)
    msg = "Expected #{node.inspect} to have an explain plan"

    assert_match SQLITE_EXPLAIN_PLAN_COLUMNS_RE, node.params[:explain_plan].join, msg
  end

  def last_node_for(options = {})
    in_transaction('sandwiches/index') do
      yield
    end
    sample = last_transaction_trace
    sample.prepare_to_send!
    last_node(sample)
  end

  def last_node(txn_sample)
    l_node = nil
    txn_sample.root_node.each_node do |node|
      l_node = node
    end
    l_node
  end

  def product_name
    if defined?(RUBY_ENGINE) && RUBY_ENGINE == "jruby"
      "JDBC"
    else
      "SQLite"
    end
  end

  def assert_datastore_metrics_recorded_exclusive(metrics, options = {})
    assert_metrics_recorded_exclusive(metrics, {:filter => /^Datastores/}.update(options))
  end
end
