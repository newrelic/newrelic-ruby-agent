# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../datastores/nosql_obfuscator'

module NewRelic::Agent::Instrumentation
  module Elasticsearch
    PRODUCT_NAME = 'Elasticsearch'
    OPERATION = 'perform_request'

    # Pattern to use with client caller location strings. Look for a location
    # that contains '/lib/elasticsearch/api/' and is NOT followed by the
    # string held in the OPERATION constant
    OPERATION_PATTERN = %r{/lib/elasticsearch/api/(?!.+#{OPERATION})}.freeze

    # Use the OPERATION_PATTERN pattern to find the appropriate caller location
    # that will contain the client instance method (example: 'search') and
    # return that method name.
    #
    # A Ruby caller location matching the OPERATION_PATTERN will contain an
    # elasticsearch client instance method name (such as "search"), and that
    # method name will be used as the operation name.
    #
    # With Ruby < 3.4 the method name is listed as:
    #
    #   `search'
    #
    # with an opening backtick and a closing single tick. And only the
    # method name itself is listed.
    #
    # With Ruby 3.4+ the method name is listed as:
    #
    #   'Elasticsearch::API::Actions#search'
    #
    # with opening and closing single ticks and the class defining the
    # instance method listed.
    #
    # (?:) = ?: prevents capturing
    # (?:`|') = allow ` or '
    # (?:.+#) = allow the class name and '#' prefix to exist but ignore it
    # ([^']+)' = after the opening ` or ', capturing everything up to the
    #            closing '.  [^']+ = one or more characters that are not '
    #
    # Example Ruby 3.3.1 input:
    #
    #   /Users/fallwith/.rubies/ruby-3.3.1/lib/ruby/gems/3.3.0/gems/elasticsearch-api-7.17.10/lib/elasticsearch/api/actions/index.rb:74:in `index'
    #
    # Example Ruby 3.4.0-preview1 input:
    #
    #   /Users/fallwith/.rubies/ruby-3.4.0-preview1/lib/ruby/gems/3.4.0+0/gems/elasticsearch-api-7.17.10/lib/elasticsearch/api/actions/index.rb:74:in 'Elasticsearch::API::Actions#index'
    #
    # Example output for both Rubies:
    #
    #   index

    INSTANCE_METHOD_PATTERN = /:in (?:`|')(?:.+#)?([^']+)'\z/.freeze

    INSTRUMENTATION_NAME = NewRelic::Agent.base_name(name)

    # We need the positional arguments `params` and `body`
    # to capture the nosql statement
    # *args protects the instrumented method if new arguments are added to
    # perform_request
    def perform_request_with_tracing(_method, _path, params = {}, body = nil, _headers = nil, *_args)
      return yield unless NewRelic::Agent::Tracer.tracing_enabled?

      NewRelic::Agent.record_instrumentation_invocation(INSTRUMENTATION_NAME)

      segment = NewRelic::Agent::Tracer.start_datastore_segment(
        product: PRODUCT_NAME,
        operation: nr_operation || OPERATION,
        host: nr_hosts[:host],
        port_path_or_id: nr_hosts[:port],
        database_name: nr_cluster_name
      )

      begin
        NewRelic::Agent::Tracer.capture_segment_error(segment) { yield }
      ensure
        if segment
          segment.notice_nosql_statement(nr_reported_query(body || params))
          segment.finish
        end
      end
    end

    private

    def nr_operation
      location = caller_locations.detect { |loc| loc.to_s.match?(OPERATION_PATTERN) }
      return unless location && location.to_s =~ INSTANCE_METHOD_PATTERN

      Regexp.last_match(1)
    end

    def nr_reported_query(query)
      return unless NewRelic::Agent.config[:'elasticsearch.capture_queries']
      return query unless NewRelic::Agent.config[:'elasticsearch.obfuscate_queries']

      NewRelic::Agent::Datastores::NosqlObfuscator.obfuscate_statement(query)
    end

    def nr_cluster_name
      return @nr_cluster_name if defined?(@nr_cluster_name)
      return if nr_hosts.empty?

      NewRelic::Agent.disable_all_tracing do
        @nr_cluster_name ||= perform_request('GET', '/').body['cluster_name']
      end
    rescue StandardError => e
      NewRelic::Agent.logger.error('Failed to get cluster name for elasticsearch', e)
      nil
    end

    def nr_hosts
      @nr_hosts ||= (transport.hosts.first || NewRelic::EMPTY_HASH)
    end
  end
end
