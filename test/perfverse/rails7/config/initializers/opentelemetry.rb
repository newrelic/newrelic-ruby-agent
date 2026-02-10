require 'opentelemetry-api'

APP_TRACER = OpenTelemetry.tracer_provider.tracer('agent-app', '0.0.0')