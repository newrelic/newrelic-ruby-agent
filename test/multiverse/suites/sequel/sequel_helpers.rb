# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module SequelHelpers
  def setup
    super

    DB.extension :newrelic_instrumentation

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
  def assert_segment_has_explain_plan( segment, msg=nil )
    msg = "Expected #{segment.inspect} to have an explain plan"
    assert_block( msg ) { segment.params[:explain_plan].join =~ SQLITE_EXPLAIN_PLAN_COLUMNS_RE }
  end

  def last_segment_for(options={})
      in_transaction('sandwiches/index') do
        yield
      end
      sample = NewRelic::Agent.instance.transaction_sampler.last_sample
      sample.prepare_to_send!
      last_segment(sample)
  end

  def last_segment(txn_sample)
    l_segment = nil
    txn_sample.root_segment.each_segment do |segment|
      l_segment = segment
    end
    l_segment
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