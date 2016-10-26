# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/instrumentation/memcache'

module NewRelic
  module Agent
    module Instrumentation
      module Memcache
        module Dalli
          extend self

          MEMCACHED = "Memcached".freeze
          METHODS = [:get, :set, :add, :incr, :decr, :delete, :replace, :append, :prepend, :cas]
          SEND_MULTIGET_METRIC_NAME = "get_multi_request".freeze
          DATASTORE_INSTANCES_SUPPORTED_VERSION = '2.6.4'

          def supports_datastore_instances?
            ::Dalli::VERSION >= DATASTORE_INSTANCES_SUPPORTED_VERSION
          end

          def instrument_methods
            if supports_datastore_instances?
              ::NewRelic::Agent::Instrumentation::Memcache.instrument_methods(::Dalli::Client, METHODS)
              instrument_multi_method :get_multi
              instrument_send_multiget
              instrument_server_for_key
            else
              ::NewRelic::Agent::Instrumentation::Memcache.instrument_methods(::Dalli::Client,
                ::NewRelic::Agent::Instrumentation::Memcache::METHODS)
            end
          end

          def instrument_server_for_key
            ::Dalli::Ring.class_eval do
              alias_method :server_for_key_without_newrelic_trace, :server_for_key

              def server_for_key key
                server = server_for_key_without_newrelic_trace key
                begin
                  if txn = ::NewRelic::Agent::Transaction.tl_current
                    segment = txn.current_segment
                    if ::NewRelic::Agent::Transaction::DatastoreSegment === segment
                      segment.host = ::NewRelic::Agent::Hostname.get_external server.hostname
                      segment.port_path_or_id = server.port
                    end
                  end
                rescue => e
                  ::NewRelic::Agent.logger.warn "unable to set instance info on datastore segment: #{e.message}"
                end
                server
              end
            end
          end

          def instrument_send_multiget
            ::Dalli::Server.class_eval do
              alias_method :send_multiget_without_newrelic_trace, :send_multiget

              def send_multiget(keys)
                external_host = ::NewRelic::Agent::Hostname.get_external(hostname)
                segment = ::NewRelic::Agent::Transaction.start_datastore_segment(MEMCACHED, SEND_MULTIGET_METRIC_NAME, nil, external_host, port)
                begin
                  send_multiget_without_newrelic_trace(keys)
                ensure
                  if ::NewRelic::Agent.config[:capture_memcache_keys]
                    ::NewRelic::Agent.instance.transaction_sampler.notice_nosql(args.first.inspect,
                                                                                (Time.now - segment.start_time).to_f) rescue nil
                  end
                  segment.finish
                end
              end
            end
          end

          def instrument_multi_method method_name
            visibility = NewRelic::Helper.instance_method_visibility ::Dalli::Client, method_name
            method_name_without = :"#{method_name}_without_newrelic_trace"

            ::Dalli::Client.class_eval do
              alias_method method_name_without, method_name

              define_method method_name do |*args, &block|
                segment = NewRelic::Agent::Transaction.start_segment "Ruby/Memcached/#{method_name}"
                begin
                  __send__ method_name_without, *args, &block
                ensure
                  segment.finish
                end
              end

              __send__ visibility, method_name
              __send__ visibility, method_name_without
            end
          end

        end
      end
    end
  end
end

DependencyDetection.defer do
  named :dalli

  depends_on do
    NewRelic::Agent::Instrumentation::Memcache.enabled?
  end

  depends_on do
    defined?(::Dalli::Client)
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Memcache instrumentation for dalli gem'
    ::NewRelic::Agent::Instrumentation::Memcache::Dalli.instrument_methods
  end
end

DependencyDetection.defer do
  named :dalli_cas_client

  depends_on do
    NewRelic::Agent::Instrumentation::Memcache.enabled?
  end

  depends_on do
    # These CAS client methods are only optionally defined if users require
    # dalli/cas/client. Use a separate dependency block so it can potentially
    # re-evaluate after they've done that require.
    defined?(::Dalli::Client) &&
      ::NewRelic::Agent::Instrumentation::Memcache.supported_methods_for(::Dalli::Client,
                                                                         CAS_CLIENT_METHODS).any?
  end

  CAS_CLIENT_METHODS = [:get_cas, :get_multi_cas, :set_cas, :replace_cas, :delete_cas]

  executes do
    ::NewRelic::Agent.logger.info 'Installing Dalli CAS Client Memcache instrumentation'
    ::NewRelic::Agent::Instrumentation::Memcache.instrument_methods(::Dalli::Client,
                                                                    CAS_CLIENT_METHODS)
  end
end
