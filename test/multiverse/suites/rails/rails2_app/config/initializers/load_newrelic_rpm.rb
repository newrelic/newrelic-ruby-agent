# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'newrelic_rpm'

# Needs to be after we've loaded the agent so we're located within our
# transaction starting middlewares
Rails.configuration.middleware.use ErrorMiddleware
