# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# File required to exist by Rails

ActionController::Routing::Routes.draw do |map|
  map.connect 'bad_instrumentation/:action', :controller => 'bad_instrumentation'
  map.connect 'error/:action',               :controller => 'error'
  map.connect 'transaction_ignorer/:action', :controller => 'transaction_ignorer'
  map.connect 'request_stats/:action',       :controller => 'request_stats'
  map.connect 'queue/:action',               :controller => 'queue'
  map.connect 'views/:action',               :controller => 'views'
  map.connect 'ignored/:action',             :controller => 'ignored'
  map.connect 'parameter_capture/:action',   :controller => 'parameter_capture'
  map.connect 'child/:action',               :controller => 'child'

  map.connect ':controller/:action'
end
