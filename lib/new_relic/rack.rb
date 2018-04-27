# frozen_string_literal: true

# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# @api public
module NewRelic
  # This module contains Rack middlewares used by the Ruby agent.
  #
  # Generally, these middlewares should be injected automatically when starting
  # your application. If automatic injection into the middleware chain is not
  # working for some reason, you may also include them manually.
  #
  #
  # @api public
  module Rack
  end
end
