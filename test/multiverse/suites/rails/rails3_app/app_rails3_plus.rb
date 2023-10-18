# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'action_controller/railtie'
require 'active_model'
require 'filtering_test_app'
# NOTE: my_app should be brought in before rails/test_help,
#       but after filtering_test_app. This is because logic to maintain
#       the test db schema will expect a Rails app to be in play.
require_relative 'my_app'
require 'rails/test_help'
