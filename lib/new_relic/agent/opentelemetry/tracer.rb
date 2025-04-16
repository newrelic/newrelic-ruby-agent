# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      # TODO: Decide if we should inherit this from the API
      class Tracer # < ::OpenTelemetry::Trace::Tracer
        attr_accessor :name, :version

        # TODO: decide if we should set up a default traver value
        # What does the API/SDK do?
        def initialize(name, version)
          @name = name # || 'newrelic_rpm'
          @version = version # || NewRelic::VERSION::STRING
        end

        def start_root_span(name, attributes: nil, links: nil, start_timestamp: nil, kind: nil)
          binding.irb
          # start_transaction?
        end

        def start_span(name, with_parent: nil, attributes: nil, links: nil, start_timestamp: nil, kind: nil)
          # TODO: copied, is this the right choice for us?
          parent_context = with_parent || find_context
          parent_span = ::OpenTelemetry::Trace.current_span(parent_context)
          parent_span_context = parent_span.context

          if parent_span_context.valid?
            parent_span_id = parent_span_context.span_id
            trace_id = parent_span_context.trace_id
          end
          # maybe we don't bother generating guids and instead just apply
          # the ones we get from NR to the spans?
          # trace_id ||= NewRelic::Agent::GuidGenerator.generate_guid
          # there's some stuff about untraced spans in the original code that
          # we're not going to account for right now
          # if OpenTelemetry::Common::Utilities.untraced?(parent_context)
          #   span_id = parent_span_id || NewRelic::Agent::GuidGenerator.generate_guid
          #   return OpenTelemetry::Trace.non_recording_span(OpenTelemetry::Trace::SpanContext.new(trace_id: trace_id, span_id: span_id))
          # end
          # maybe we don't need to generate guids and just apply the ones from
          # NR objects to the spans?
          # span_id = NewRelic::Agent::GuidGenerator.generate_guid
          # stuff about samplers that we're not addressing yet
          # result = @sampler.should_sample?(trace_id: trace_id, parent_context: parent_context, links: links, name: name, kind: kind, attributes: attributes)
          trace_flags = 1

          # Otel sdk configurator assigns an ID generator
          # this one is based on the OTel API
          # for now, setting the ID generator to use what we'd use for our traces
          # trace_id ||= NewRelic::GuidGenerator.generate_guid
          # start_segment maybe instead? But if you don't give it a parent, it just takes the current context and will create a new trace, right?
          # NewRelic::Agent::Tracer.start_transaction_or_segment
          # binding.irb
          segment = NewRelic::Agent::Tracer.start_segment(
            name: name,
            start_time: start_timestamp
            # parent: with_parent || NewRelic::Agent::Tracer.current_transaction
          )
          context = ::OpenTelemetry::Trace::SpanContext.new(trace_id: segment.transaction.trace_id, span_id: segment.guid)
          span = ::OpenTelemetry::Trace::Span.new(span_context: context)
        end

        def in_span(name, attributes: nil, links: nil, start_timestamp: nil, kind: nil)
          # start_segment_or_transaction ?
          case kind
          when :internal
            begin
              # what's the right category for an internal?
              finishable = nil
              span = nil

              # maybe check to see if there's a current transaction, if so, add it; if not, start one?
              # TODO: check to see if we have the right category
              # how is node setting the category?
              finishable = NewRelic::Agent::Tracer.start_transaction_or_segment(name: name, category: :other)
              # will it always be a segment? # when would it be a transaction?
              if finishable.is_a?(NewRelic::Agent::Transaction::Segment)
                span = Span.new(segment: finishable, transaction: finishable.transaction)
              else
                # this happens, not sure what test case
                # also happens in the "outer" example for simple.rb
                span = Span.new(segment: finishable.segments.first, transaction: finishable)
              end

              ::OpenTelemetry::Trace.with_span(span) do
                yield
              end
            ensure
              finishable&.finish
            end
          when :client
            # abstract this into a separate class
            begin
              # skipping the wrapped_request stuff from NR instrumentation for now
              segment = NewRelic::Agent::Tracer.start_external_request_segment(
                # otel tracers generally are named after the library
                # that's generating the trace
                library: self.name,
                uri: name,
                # does this change based on semconv?
                procedure: attributes['http.method'],
                start_time: start_timestamp
                # parent: ----
              )
              # do we try to capture segment errors?
              NewRelic::Agent::Tracer.capture_segment_error(segment) { yield(segment) }
            ensure
              segment&.finish
            end
          when :server
            # attributes = {"component" => "http",
            #  "http.method" => "GET",
            #  "http.route" => "/hello",
            #  "http.url" => "/hello"}
            # span name is "/hello"
            # set as partial_name: "Nested/Controller//hello"
            # set as :name => "/hello"
            # Should they be named like NR names?
            # sincei t's a block, use in_transaction
            # also considered #start_transaction_or_segment
            # NewRelic::Agent::Tracer.in_transaction(
            begin
              finishable = NewRelic::Agent::Tracer.start_transaction_or_segment(
                name: name,
                category: :web
                # do we want the request?
                # what are all the options for :options?
              )
              yield(finishable)
            rescue Exception => e
              binding.irb
              NewRelic::Agent.notice_error(e)
              raise e
            ensure
              finishable&.finish
            end
          else
            binding.irb
          end
        end

        private

        def find_context
          ::OpenTelemetry::Context.current == ::OpenTelemetry::Trace::Span::INVALID ? ::OpenTelemetry::Context.empty : ::OpenTelemetry::Context.current
        end
      end
    end
  end
end
