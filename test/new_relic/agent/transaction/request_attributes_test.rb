# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'
require 'new_relic/agent/transaction/request_attributes'
require 'rack'

module NewRelic
  module Agent
    class Transaction
      class RequestAttributesTest < Minitest::Test
        # a full environment hash to initialize a Rack request with
        ENV_HASH = {'GATEWAY_INTERFACE' => 'CGI/1.1',
                    'PATH_INFO' => '/en-gb',
                    'QUERY_STRING' => '',
                    'REMOTE_ADDR' => '23.66.3.4',
                    'REMOTE_HOST' => 'lego.com',
                    'REQUEST_METHOD' => 'GET',
                    'REQUEST_URI' => 'https://lego.com:443/en-gb',
                    'SCRIPT_NAME' => '',
                    'SERVER_NAME' => 'lego.com',
                    'SERVER_PORT' => '443',
                    'SERVER_PROTOCOL' => 'HTTPS/1.1',
                    'SERVER_SOFTWARE' => 'WEBrick/867.53.09 (Ruby/6.7.5/2035-10-06)',
                    'HTTP_HOST' => 'lego.com:443',
                    'HTTP_ACCEPT_LANGUAGE' => 'en-GB,en;q=0.8',
                    'HTTP_CACHE_CONTROL' => 'max-age=0',
                    'HTTP_ACCEPT_ENCODING' => 'gzip',
                    'HTTP_ACCEPT' => 'text/html, application/xml;q=0.9, */*;q=0.8',
                    'HTTP_USER_AGENT' => 'Lernaean/Hydra/700bc (Slackware 27.0; Linux; x128)',
                    'rack.version' => [11, 38],
                    'rack.url_scheme' => 'https',
                    'HTTP_VERSION' => 'HTTPS/1.1',
                    'REQUEST_PATH' => '/en-gb',
                    'CONTENT_LENGTH' => 2049,
                    'CONTENT_TYPE' => 'application/x-7z-compressed',
                    'CUSTOM_HEADER' => 'Bram Moolenaar',
                    'HTTP_REFERER' => 'https://www.bitmapbooks.com/collections/all-books/products/' +
                      'sega-master-system-a-visual-compendium'}

        RACK_REQUEST = ::Rack::Request.new(ENV_HASH)

        # a mapping between RequestAttributes methods and the corresponding agent attributes and values
        BASE_HEADERS_MAP = {accept: {agent_attribute: :'request.headers.accept',
                                     value: ENV_HASH['HTTP_ACCEPT']},
                            content_length: {agent_attribute: :'request.headers.contentLength',
                                             value: ENV_HASH['CONTENT_LENGTH']},
                            content_type: {agent_attribute: :'request.headers.contentType',
                                           value: ENV_HASH['CONTENT_TYPE']},
                            host: {agent_attribute: :'request.headers.host',
                                   value: RACK_REQUEST.host},
                            port: {agent_attribute: nil, # no agent attribute
                                   value: RACK_REQUEST.port},
                            referer: {agent_attribute: nil, # only present on errors
                                      value: ENV_HASH['HTTP_REFERER']},
                            request_method: {agent_attribute: :'request.method',
                                             value: ENV_HASH['REQUEST_METHOD']},
                            request_path: {agent_attribute: :'request.uri',
                                           value: ENV_HASH['REQUEST_PATH']},
                            user_agent: {agent_attribute: :'request.headers.userAgent',
                                         value: ENV_HASH['HTTP_USER_AGENT']}}.freeze

        # a mapping between agent attributes and values for all expected "other" headers
        OTHER_HEADERS_MAP = {'request.headers.gatewayInterface': ENV_HASH['GATEWAY_INTERFACE'],
                             'request.headers.queryString': ENV_HASH['QUERY_STRING'],
                             'request.headers.remoteAddr': ENV_HASH['REMOTE_ADDR'],
                             'request.headers.scriptName': ENV_HASH['SCRIPT_NAME'],
                             'request.headers.serverName': ENV_HASH['SERVER_NAME'],
                             'request.headers.serverProtocol': ENV_HASH['SERVER_PROTOCOL'],
                             'request.headers.serverSoftware': ENV_HASH['SERVER_SOFTWARE'],
                             'request.headers.httpHost': ENV_HASH['HTTP_HOST'],
                             'request.headers.httpAcceptLanguage': ENV_HASH['HTTP_ACCEPT_LANGUAGE'],
                             'request.headers.httpCacheControl': ENV_HASH['HTTP_CACHE_CONTROL'],
                             'request.headers.httpAcceptEncoding': ENV_HASH['HTTP_ACCEPT_ENCODING'],
                             'request.headers.rack.version': ENV_HASH['rack.version'],
                             'request.headers.rack.urlScheme': ENV_HASH['rack.url_scheme'],
                             'request.headers.httpVersion': ENV_HASH['HTTP_VERSION'],
                             'request.headers.requestPath': ENV_HASH['REQUEST_PATH'],
                             'request.headers.customHeader': ENV_HASH['CUSTOM_HEADER']}.freeze

        # these are special cased base headers
        #   - port: always available as an attribute on the RequestAttributes
        #           instane, but not reported as an agent attribute by default
        #   - referer: by default only routed to 1 destination
        #   - uri: by default only routed to 2 destinations
        #
        # when allow_all_headers is enabled, all 3 should appear as agent
        # attributes for ALL destinations.
        #
        # the mapping here is agent attribute key => expected value
        CONDITIONAL_BASE_HEADERS_MAP = {'request.headers.port': ENV_HASH['SERVER_PORT'].to_i,
                                        'request.headers.referer': ENV_HASH['HTTP_REFERER'],
                                        'request.uri': ENV_HASH['REQUEST_PATH']}

        def test_tolerates_request_without_desired_methods
          request = stub('request')
          attrs = RequestAttributes.new(request)

          assert_equal '/', attrs.request_path
          assert_nil attrs.referer
          assert_nil attrs.content_length
          assert_nil attrs.content_type
          assert_nil attrs.host
          assert_nil attrs.user_agent
          assert_nil attrs.request_method
        end

        def test_sets_referer_from_request
          request = stub('request', :referer => 'http://site.com/page')
          attrs = RequestAttributes.new(request)

          assert_equal 'http://site.com/page', attrs.referer
        end

        def test_sets_accept_from_request_headers
          request = stub('request', :env => {'HTTP_ACCEPT' => 'application/json'})
          attrs = RequestAttributes.new(request)

          assert_equal 'application/json', attrs.accept
        end

        def test_sets_content_length_from_request
          request = stub('request', :content_length => '111')
          attrs = RequestAttributes.new(request)

          assert_equal 111, attrs.content_length
        end

        def test_sets_content_type_from_request
          request = stub('request', :content_type => 'application/json')
          attrs = RequestAttributes.new(request)

          assert_equal 'application/json', attrs.content_type
        end

        def test_sets_host_from_request
          request = stub('request', :host => 'localhost')
          attrs = RequestAttributes.new(request)

          assert_equal 'localhost', attrs.host
        end

        def test_sets_port_from_request
          request = stub('request', :port => '3000')
          attrs = RequestAttributes.new(request)

          assert_equal 3000, attrs.port
        end

        def test_sets_user_agent_from_request
          request = stub('request', :user_agent => 'use this!')
          attrs = RequestAttributes.new(request)

          assert_equal 'use this!', attrs.user_agent
        end

        def test_sets_method_from_request
          request = stub('request', :request_method => 'POST')
          attrs = RequestAttributes.new(request)

          assert_equal 'POST', attrs.request_method
        end

        def test_by_default_only_a_base_set_of_request_headers_are_captured
          skip_unless_minitest5_or_above

          with_config(allow_all_headers: false, :'attributes.include' => [], :'attributes.exclude' => []) do
            attrs = RequestAttributes.new(RACK_REQUEST)

            BASE_HEADERS_MAP.each do |method, definition|
              assert_equal definition[:value],
                attrs.send(method),
                "Expected RequestAttributes##{method} to yield >#{definition[:value]}<, got >#{attrs.send(method)}<"
            end
            assert_equal NewRelic::EMPTY_HASH, attrs.other_headers, 'Did not expect to find other headers'
          end
        end

        def test_if_allow_all_headers_is_specified_then_allow_them_all
          skip 'Test requires Rack v2+' if Rack.respond_to?(:release) && Rack.release.start_with?('1.')
          skip_unless_minitest5_or_above

          with_config(allow_all_headers: true) do
            attrs = RequestAttributes.new(RACK_REQUEST)

            BASE_HEADERS_MAP.each do |method, definition|
              assert_equal definition[:value],
                attrs.send(method),
                "Expected RequestAttributes##{method} to yield >#{definition[:value]}<, got >#{attrs.send(method)}<"
            end

            assert_equal attrs.other_headers.size, OTHER_HEADERS_MAP.keys.size

            attrs.other_headers.each do |header, value|
              assert_equal OTHER_HEADERS_MAP[header], value, "Expected attribute '#{header}' to have value " +
                "'#{OTHER_HEADERS_MAP[header]}', but it had value '#{value}'"
            end
          end
        end

        def test_agent_attributes_on_transaction_with_default_config
          in_transaction do |txn|
            attrs = RequestAttributes.new(RACK_REQUEST)
            attrs.assign_agent_attributes(txn)
            txn_attrs = txn.attributes.agent_attributes_for(NewRelic::Agent::AttributeFilter::DST_TRANSACTION_TRACER)
            BASE_HEADERS_MAP.values do |definition|
              agent_attr = definition[:agent_attribute]
              next unless agent_attr

              assert_equal definition[:value],
                txn_attrs[agent_attr],
                "Agent attribute '#{agent_attr}' had value '#{txn_attrs[agent_attr]}' instead of " +
                  "'#{definition[:value]}'"
            end
          end
        end

        def test_the_use_of_attributes_include_as_an_allowlist
          skip_unless_minitest5_or_above

          with_config(allow_all_headers: true,
            'attributes.include': %w[request.headers.contentType],
            'attributes.exclude': %w[request.*]) do
            attrs = RequestAttributes.new(RACK_REQUEST)

            in_transaction do |txn|
              attrs = RequestAttributes.new(RACK_REQUEST)
              attrs.assign_agent_attributes(txn)
              txn_attrs = txn.attributes.agent_attributes_for(NewRelic::Agent::AttributeFilter::DST_TRANSACTION_TRACER)

              assert_equal 1, txn_attrs.size, 'Expected only a single agent attribute'
              assert_equal BASE_HEADERS_MAP[:content_type][:value], txn_attrs.values.first
            end
          end
        end

        def test_the_use_of_attributes_exclude_as_a_blocklist
          skip 'Test requires Rack v2+' if Rack.respond_to?(:release) && Rack.release.start_with?('1.')
          skip_unless_minitest5_or_above

          excluded_header = :'request.headers.customHeader'
          with_config(allow_all_headers: true,
            'attributes.include': %w[],
            'attributes.exclude': [excluded_header.to_s]) do
            attrs = RequestAttributes.new(RACK_REQUEST)

            in_transaction do |txn|
              attrs = RequestAttributes.new(RACK_REQUEST)
              attrs.assign_agent_attributes(txn)
              txn_attrs = txn.attributes.agent_attributes_for(NewRelic::Agent::AttributeFilter::DST_TRANSACTION_TRACER)
              expected = {}
              BASE_HEADERS_MAP.each do |_k, definition|
                expected[definition[:agent_attribute]] = definition[:value] if definition[:agent_attribute]
              end
              OTHER_HEADERS_MAP.each do |header, value|
                next if header == excluded_header

                expected[header] = value
              end
              CONDITIONAL_BASE_HEADERS_MAP.each do |header, value|
                next if expected.key?(header)

                expected[header] = value
              end

              assert_equal expected.keys.size, txn_attrs.size, "Expected #{expected.keys.size} header attributes, " +
                "but found #{txn_attrs.size}"
              expected.each do |header, value|
                assert_equal value, txn_attrs[header], "Expected header attribute '#{header}' to have value " +
                  "'#{value}', but it had value '#{txn_attrs[header]}' instead."
              end
            end
          end
        end
      end
    end
  end
end
