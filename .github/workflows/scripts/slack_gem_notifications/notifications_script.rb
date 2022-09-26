# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# This script runs on a 24 hour cycle via gem_notifications.yml and sends Slack updates for new gem version releases.

require_relative 'notifications_methods'

check_for_updates(ARGV)
