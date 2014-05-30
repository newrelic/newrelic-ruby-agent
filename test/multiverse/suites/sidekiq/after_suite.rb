# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

if defined?(SidekiqServer)
  SidekiqServer.instance.stop
end
