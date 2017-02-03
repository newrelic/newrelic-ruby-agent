# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module TransactionSampleTestHelper
  module_function
  def make_sql_transaction(*sql)
    sampler = nil
    state = NewRelic::Agent::TransactionState.tl_get

    in_transaction('/path') do
      sampler = NewRelic::Agent.instance.transaction_sampler
      sampler.notice_push_frame(state, "a")
      explainer = NewRelic::Agent::Instrumentation::ActiveRecord::EXPLAINER
      sql.each {|sql_statement| sampler.notice_sql(sql_statement, {:adapter => "mysql"}, 0, state, explainer) }
      sleep 0.02
      yield if block_given?
      sampler.notice_pop_frame(state, "a")
    end

    return sampler.last_sample
  end

  def run_sample_trace(path='/path')
    sampler = nil
    state = NewRelic::Agent::TransactionState.tl_get

    request = stub(:path => path)

    in_transaction("Controller/sandwiches/index", :request => request) do
      sampler = NewRelic::Agent.instance.transaction_sampler
      sampler.notice_sql("SELECT * FROM sandwiches WHERE bread = 'wheat'", {}, 0, state)
      sampler.notice_push_frame(state, "ab")
      sampler.notice_sql("SELECT * FROM sandwiches WHERE bread = 'white'", {}, 0, state)
      yield sampler if block_given?
      sampler.notice_pop_frame(state, "ab")
      sampler.notice_push_frame(state, "lew")
      sampler.notice_sql("SELECT * FROM sandwiches WHERE bread = 'french'", {}, 0, state)
      sampler.notice_pop_frame(state, "lew")
    end

    return sampler.last_sample
  end
end
