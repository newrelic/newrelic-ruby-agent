#!/usr/bin/env ruby
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

ENV["NEW_RELIC_LOG_FILE_PATH"] = "STDOUT"

require 'newrelic_rpm'

NewRelic::Agent.manual_start(:env => :development)
