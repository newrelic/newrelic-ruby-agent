# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/instrumentation/rack'

class TestingApp

  attr_accessor :response, :headers

  def initialize
    reset_headers
  end

  def reset_headers
    @headers = {'Content-Type' => 'text/html'}
  end

  def call(env)
    request = Rack::Request.new(env)
    params = request.params
    if params['transaction_name']
      opts = {}
      if params['transaction_category']
        opts[:category] = params['transaction_category']
        NewRelic::Agent::Transaction.stubs(:transaction_category_is_web?).returns(true)
      end
      NewRelic::Agent.set_transaction_name(params['transaction_name'], opts)
    end
    if params['cross_app_caller']
      NewRelic::Agent::TransactionState.tl_get.is_cross_app_caller = true
    end
    stub_transaction_guid(params['guid']) if params['guid']
    sleep(params['sleep'].to_f) if params['sleep']
    [200, headers, [response]]
  end

  include NewRelic::Agent::Instrumentation::Rack
end
