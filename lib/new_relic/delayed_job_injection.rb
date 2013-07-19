# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module DelayedJobInjection
    extend self
    attr_accessor :worker_name
  end
end
