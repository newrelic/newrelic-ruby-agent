# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'opentelemetry-api'

APP_TRACER = OpenTelemetry.tracer_provider.tracer('agent-app', '0.0.0')