# encoding: utf-8
# This file is distributed under New Relic"s license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# This is a simple test app for testing parameter filtering as provided by
# the NewRelic::Agent:ParameterFiltering module.

class FilteringTestApp
  def call(env)
    req = Rack::Request.new(env)
    txn = ::NewRelic::Agent::Transaction.tl_current
    params = req.params
    filtered = ::NewRelic::Agent::ParameterFiltering.apply_filters(env, params)
    txn.filtered_params = filtered
    txn.merge_request_parameters(filtered)
    raise "Intentional error" if params["raise"]
    [200, {}, ["Filters applied"]]
  end
end
