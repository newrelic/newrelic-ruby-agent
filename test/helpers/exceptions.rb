# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

module NewRelic
  module TestHelpers
    module Exceptions
      class TestError < StandardError; end
      class IgnoredError < StandardError; end
      class ServerIgnoredError < StandardError; end
      class TestRuntimeError < RuntimeError; end
      class ParentException < Exception; end
      class ChildException < ParentException; end
    end
  end
end
