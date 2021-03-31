# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module Instrumentation
      module Memcache

        module Tracer
          MULTIGET_METRIC_NAME = "get_multi_request"
          MEMCACHED = "Memcached"

          def with_newrelic_tracing operation, *args
            segment = NewRelic::Agent::Tracer.start_datastore_segment(
              product: MEMCACHED,
              operation: operation
            )
            begin
              NewRelic::Agent::Tracer.capture_segment_error(segment) { yield }
            ensure
              if NewRelic::Agent.config[:capture_memcache_keys]
                segment.notice_nosql_statement "#{operation} #{args.first.inspect}"
              end
              segment.finish if segment
            end
          end

          def server_for_key_with_newrelic_tracing
            yield.tap do |server|
              begin
                if txn = ::NewRelic::Agent::Tracer.current_transaction
                  segment = txn.current_segment
                  if ::NewRelic::Agent::Transaction::DatastoreSegment === segment
                    ::NewRelic::Agent::Instrumentation::Memcache::Helper.assign_instance_to(segment, server)
                  end
                end
              rescue => e
                ::NewRelic::Agent.logger.warn "Unable to set instance info on datastore segment: #{e.message}"
              end
            end
          end

          def send_multiget_with_newrelic_tracing keys
            segment = ::NewRelic::Agent::Tracer.start_datastore_segment(
              product: MEMCACHED,
              operation: MULTIGET_METRIC_NAME
            )
            ::NewRelic::Agent::Instrumentation::Memcache::Helper.assign_instance_to(segment, self)

            begin
              NewRelic::Agent::Tracer.capture_segment_error(segment) { yield }
            ensure
              if ::NewRelic::Agent.config[:capture_memcache_keys]
                segment.notice_nosql_statement "#{MULTIGET_METRIC_NAME} #{keys.inspect}"
              end
              segment.finish if segment
            end
          end

          def get_multi_with_newrelic_tracing keys
            segment = ::NewRelic::Agent::Tracer.start_datastore_segment(
              product: MEMCACHED,
              operation: "get_multi"
            )
            ::NewRelic::Agent::Instrumentation::Memcache::Helper.assign_instance_to(segment, self)

            begin
              NewRelic::Agent::Tracer.capture_segment_error(segment) { yield }
            ensure
              if ::NewRelic::Agent.config[:capture_memcache_keys]
                segment.notice_nosql_statement "#{MULTIGET_METRIC_NAME} #{keys.inspect}"
              end
              segment.finish if segment
            end
          end
        end

      end
    end
  end
end

