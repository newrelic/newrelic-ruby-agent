#!/usr/bin/env ruby
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

ENV['NEW_RELIC_LOG_FILE_PATH'] = 'STDOUT'

require 'newrelic_rpm'

NewRelic::Agent.manual_start(:env => 'production')
