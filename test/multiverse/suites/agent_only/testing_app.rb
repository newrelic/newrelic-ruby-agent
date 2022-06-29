# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'new_relic/agent/instrumentation/rack'

class TestingApp
  attr_accessor :response, :headers

  def initialize
    @headers = {'Content-Type' => 'text/html'}
  end

  def call(env)
    request = Rack::Request.new(env)
    params = request.params
    if params['fail']
      raise "O_o"
    end

    if params['transaction_name']
      opts = {}
      if params['transaction_category']
        opts[:category] = params['transaction_category']
        NewRelic::Agent::Tracer.current_transaction.stubs(:similar_category?).returns true
      end
      NewRelic::Agent.set_transaction_name(params['transaction_name'], opts)
    end
    if params['cross_app_caller']
      NewRelic::Agent::Transaction.tl_current.distributed_tracer.is_cross_app_caller = true
    end
    stub_transaction_guid(params['guid']) if params['guid']
    sleep(params['sleep'].to_f) if params['sleep']
    [200, headers, [response]]
  end
end

class TestingBackgroundJob
  FIRST_NAME = "OtherTransaction/Custom/TestingBackgroundJob/first"
  SECOND_NAME = "OtherTransaction/Custom/TestingBackgroundJob/second"

  def first(awhile = nil)
    job(FIRST_NAME, awhile)
  end

  def second(awhile = nil)
    job(SECOND_NAME, awhile)
  end

  def job(name, awhile)
    ::NewRelic::Agent::Tracer.in_transaction(name: name, category: :other) do
      sleep(awhile) if awhile
    end
  end
end
