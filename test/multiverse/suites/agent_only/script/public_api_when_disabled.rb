#!/usr/bin/env ruby
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

ENV["NEW_RELIC_LOG_FILE_PATH"] = "STDOUT"

# This file tries to require the minimum amount of the agent, and then call
# public API methods on it to ensure that they don't raise exceptions. It is
# expected to be called from a driver test which will check for failure in the
# status code and/or output.

require 'new_relic/agent'

NewRelic::Agent.record_metric("Custom/Record", 1)
NewRelic::Agent.increment_metric("Custom/Increment", 1)

NewRelic::Agent.require_test_helper
NewRelic::Agent.add_instrumentation("*_foobar.rb")

NewRelic::Agent.ignore_error_filter do
end

NewRelic::Agent.notice_error(StandardError.new("Always an option"))

NewRelic::Agent.record_custom_event(:DontStart, :dont => "even")

NewRelic::Agent.ignore_transaction
NewRelic::Agent.ignore_apdex
NewRelic::Agent.ignore_enduser

NewRelic::Agent.disable_all_tracing do
end

NewRelic::Agent.disable_transaction_tracing do
end

NewRelic::Agent.disable_sql_recording do
end

NewRelic::Agent.set_transaction_name("Something/Different")
NewRelic::Agent.get_transaction_name

NewRelic::Agent.with_database_metric_name("Model", "Method") do
end

NewRelic::Agent.set_sql_obfuscator do
end

NewRelic::Agent.browser_timing_header

NewRelic::Agent.add_custom_attributes(:custom => "attributes")

NewRelic::Agent.drop_buffered_data

NewRelic::Agent.after_fork(options = {})
NewRelic::Agent.shutdown(options = {})
