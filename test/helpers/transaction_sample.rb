# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module TransactionSampleTestHelper
  module_function

  def make_sql_transaction(*sql)
    sampler = nil
    state = NewRelic::Agent::Tracer.state

    in_transaction('/path') do
      sampler = NewRelic::Agent.instance.transaction_sampler
      sampler.notice_push_frame(state, "a")
      explainer = NewRelic::Agent::Instrumentation::ActiveRecord::EXPLAINER
      sql.each { |sql_statement| sampler.notice_sql(sql_statement, {:adapter => "mysql"}, 0, state, explainer) }
      sleep 0.02
      yield if block_given?
      sampler.notice_pop_frame(state, "a")
    end

    return sampler.last_sample
  end
end
