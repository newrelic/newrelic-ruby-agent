# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# These are hacks to make the 'rails' multiverse test suite compatible with
# Rails v7.1 released on 2023-10-05.
#
# TODO: refactor these out with non-hack replacements as time permits

if Gem::Version.new(Rails.version) >= Gem::Version.new('7.1.0')
  # NoMethodError (undefined method `to_ary' for an instance of ActionController::Streaming::Body):
  # actionpack (7.1.0) lib/action_dispatch/http/response.rb:107:in `to_ary'
  # actionpack (7.1.0) lib/action_dispatch/http/response.rb:509:in `to_ary'
  # rack (3.0.8) lib/rack/body_proxy.rb:41:in `method_missing'
  # rack (3.0.8) lib/rack/etag.rb:32:in `call'
  # newrelic-ruby-agent/lib/new_relic/agent/instrumentation/middleware_tracing.rb:99:in `call'
  require 'action_controller/railtie'
  class ActionController::Streaming::Body
    def to_ary
      self
    end
  end
end
