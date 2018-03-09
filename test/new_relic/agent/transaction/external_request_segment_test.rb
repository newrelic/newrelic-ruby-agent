# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

require 'new_relic/agent/transaction'
require 'new_relic/agent/transaction/external_request_segment'

module NewRelic
  module Agent
    class Transaction
      class ExternalRequestSegmentTest < Minitest::Test
        class RequestWrapper
          attr_reader :headers

          def initialize headers = {}
            @headers = headers
          end

          def [] key
            @headers[key]
          end

          def []= key, value
            @headers[key] = value
          end

          def host_from_header
            self['host']
          end
        end

        TRANSACTION_GUID = 'BEC1BC64675138B9'

        def setup
          @obfuscator = NewRelic::Agent::Obfuscator.new "jotorotoes"
          CrossAppTracing.stubs(:obfuscator).returns(@obfuscator)
          CrossAppTracing.stubs(:valid_encoding_key?).returns(true)
        end

        def teardown
          NewRelic::Agent.drop_buffered_data
        end

        def test_generates_expected_name
          segment = ExternalRequestSegment.new "Typhoeus", "http://remotehost.com/blogs/index", "GET"
          assert_equal "External/remotehost.com/Typhoeus/GET", segment.name
        end

        def test_downcases_hostname
          segment = ExternalRequestSegment.new "Typhoeus", "http://ReMoTeHoSt.Com/blogs/index", "GET"
          assert_equal "External/remotehost.com/Typhoeus/GET", segment.name
        end

        def test_segment_does_not_record_metrics_outside_of_txn
          segment = ExternalRequestSegment.new "Net::HTTP", "http://remotehost.com/blogs/index", "GET"
          segment.finish

          refute_metrics_recorded [
            "External/remotehost.com/Net::HTTP/GET",
            "External/all",
            "External/remotehost.com/all",
            "External/allWeb",
            ["External/remotehost.com/Net::HTTP/GET", "test"]
          ]
        end

        def test_segment_records_expected_metrics_for_non_cat_txn
          in_transaction "test", :category => :controller do
            segment = Transaction.start_external_request_segment(
              library: "Net::HTTP",
              uri: "http://remotehost.com/blogs/index",
              procedure: "GET"
            )
            segment.finish
          end

          expected_metrics = [
            "External/remotehost.com/Net::HTTP/GET",
            "External/all",
            "External/remotehost.com/all",
            "External/allWeb",
            ["External/remotehost.com/Net::HTTP/GET", "test"]
          ]

          if Agent.config[:'distributed_tracing.enabled']
            expected_metrics << "DurationByCaller/Unknown/Unknown/Unknown/Unknown/all"
            expected_metrics << "DurationByCaller/Unknown/Unknown/Unknown/Unknown/allWeb"
          end

          assert_metrics_recorded expected_metrics
        end

        def test_segment_records_noncat_metrics_when_cat_disabled
          request = RequestWrapper.new
          response = {
            'X-NewRelic-App-Data' => make_app_data_payload("1#1884", "txn-name", 2, 8, 0, TRANSACTION_GUID)
          }

          with_config(cat_config.merge({:"cross_application_tracer.enabled" => false})) do
            in_transaction "test", :category => :controller do
              segment = Transaction.start_external_request_segment(
                library: "Net::HTTP",
                uri: "http://remotehost.com/blogs/index",
                procedure: "GET"
              )
              segment.add_request_headers request
              segment.read_response_headers response
              segment.finish
            end
          end

          expected_metrics = [
            "External/remotehost.com/Net::HTTP/GET",
            "External/all",
            "External/remotehost.com/all",
            "External/allWeb",
            ["External/remotehost.com/Net::HTTP/GET", "test"]
          ]

          if Agent.config[:'distributed_tracing.enabled']
            expected_metrics << "DurationByCaller/Unknown/Unknown/Unknown/Unknown/all"
            expected_metrics << "DurationByCaller/Unknown/Unknown/Unknown/Unknown/allWeb"
          end

          assert_metrics_recorded expected_metrics
        end

        def test_segment_records_noncat_metrics_without_valid_cross_process_id
          request = RequestWrapper.new
          response = {
            'X-NewRelic-App-Data' => make_app_data_payload("1#1884", "txn-name", 2, 8, 0, TRANSACTION_GUID)
          }

          with_config(cat_config.merge({:cross_process_id => ''})) do
            in_transaction "test", :category => :controller do
              segment = Transaction.start_external_request_segment(
                library: "Net::HTTP",
                uri: "http://remotehost.com/blogs/index",
                procedure: "GET"
              )
              segment.add_request_headers request
              segment.read_response_headers response
              segment.finish
            end
          end

          expected_metrics = [
            "External/remotehost.com/Net::HTTP/GET",
            "External/all",
            "External/remotehost.com/all",
            "External/allWeb",
            ["External/remotehost.com/Net::HTTP/GET", "test"]
          ]

          if Agent.config[:'distributed_tracing.enabled']
            expected_metrics << "DurationByCaller/Unknown/Unknown/Unknown/Unknown/all"
            expected_metrics << "DurationByCaller/Unknown/Unknown/Unknown/Unknown/allWeb"
          end

          assert_metrics_recorded expected_metrics
        end

        def test_segment_records_noncat_metrics_without_valid_encoding_key
          CrossAppTracing.unstub(:valid_encoding_key?)
          request = RequestWrapper.new
          response = {
            'X-NewRelic-App-Data' => make_app_data_payload("1#1884", "txn-name", 2, 8, 0, TRANSACTION_GUID)
          }

          with_config(cat_config.merge({:encoding_key => ''})) do
            in_transaction "test", :category => :controller do
              segment = Transaction.start_external_request_segment(
                library: "Net::HTTP",
                uri: "http://remotehost.com/blogs/index",
                procedure: "GET"
              )
              segment.add_request_headers request
              segment.read_response_headers response
              segment.finish
            end
          end

          expected_metrics = [
            "External/remotehost.com/Net::HTTP/GET",
            "External/all",
            "External/remotehost.com/all",
            "External/allWeb",
            ["External/remotehost.com/Net::HTTP/GET", "test"]
          ]

          if Agent.config[:'distributed_tracing.enabled']
            expected_metrics << "DurationByCaller/Unknown/Unknown/Unknown/Unknown/all"
            expected_metrics << "DurationByCaller/Unknown/Unknown/Unknown/Unknown/allWeb"
          end

          assert_metrics_recorded expected_metrics
        end

        def test_segment_records_expected_metrics_for_cat_transaction
          response = {
            'X-NewRelic-App-Data' => make_app_data_payload("1#1884", "txn-name", 2, 8, 0, TRANSACTION_GUID)
          }

          with_config cat_config do
            in_transaction "test", :category => :controller do |txn|
              segment = Transaction.start_external_request_segment(
                library: "Net::HTTP",
                uri: "http://newrelic.com/blogs/index",
                procedure: "GET"
              )
              segment.read_response_headers response
              segment.finish
            end
          end

          expected_metrics = [
            "ExternalTransaction/newrelic.com/1#1884/txn-name",
            "ExternalApp/newrelic.com/1#1884/all",
            "External/all",
            "External/newrelic.com/all",
            "External/allWeb",
            ["ExternalTransaction/newrelic.com/1#1884/txn-name", "test"]
          ]

          if Agent.config[:'distributed_tracing.enabled']
            expected_metrics << "DurationByCaller/Unknown/Unknown/Unknown/Unknown/all"
            expected_metrics << "DurationByCaller/Unknown/Unknown/Unknown/Unknown/allWeb"
          end

          assert_metrics_recorded expected_metrics
        end

        def test_proper_metrics_recorded_for_distributed_trace_on_receiver
          with_config(:'distributed_tracing.enabled' => true,
                      :trusted_account_ids => [190]) do
            request = RequestWrapper.new
            payload = nil

            with_config application_id: "46954", cross_process_id: "190#222" do
              in_transaction do |txn|
                payload = txn.create_distributed_trace_payload
              end
            end

            NewRelic::Agent.drop_buffered_data

            in_transaction "test_txn2", :category => :controller do |txn|
              txn.accept_distributed_trace_payload payload.to_json
              segment = Transaction.start_external_request_segment(
                library: "Net::HTTP",
                uri: "http://newrelic.com/blogs/index",
                procedure: "GET"
              )
              segment.add_request_headers request
              segment.finish
            end

            expected_metrics = [
              "External/all",
              "External/newrelic.com/all",
              "External/allWeb",
              "DurationByCaller/#{payload.parent_type}/#{payload.caller_account_id}/#{payload.parent_app_id}/transport/all",
              "DurationByCaller/#{payload.parent_type}/#{payload.caller_account_id}/#{payload.parent_app_id}/transport/allWeb",
              "TransportDuration/#{payload.parent_type}/#{payload.caller_account_id}/#{payload.parent_app_id}/transport/all",
              "TransportDuration/#{payload.parent_type}/#{payload.caller_account_id}/#{payload.parent_app_id}/transport/allWeb",
              ["External/newrelic.com/Net::HTTP/GET", "test_txn2"]
            ]

            assert_metrics_recorded expected_metrics
          end
        end

        def test_proper_metrics_recorded_for_distributed_trace_on_receiver_when_error_occurs
          with_config(
            :'distributed_tracing.enabled' => true,
            :trusted_account_ids => [190]) do
            request = RequestWrapper.new
            payload = nil

            with_config application_id: "46954", cross_process_id: "190#222" do
              in_transaction do |txn|
                payload = txn.create_distributed_trace_payload
              end
            end

            NewRelic::Agent.drop_buffered_data

            in_transaction "test_txn2", :category => :controller do |txn|
              txn.accept_distributed_trace_payload payload.to_json
              segment = Transaction.start_external_request_segment(
                library: "Net::HTTP",
                uri: "http://newrelic.com/blogs/index",
                procedure: "GET"
              )
              segment.add_request_headers request
              segment.finish
              NewRelic::Agent.notice_error StandardError.new("Sorry!")
            end

            expected_metrics = [
              "External/all",
              "External/newrelic.com/all",
              "External/allWeb",
              "DurationByCaller/#{payload.parent_type}/#{payload.caller_account_id}/#{payload.parent_app_id}/transport/all",
              "DurationByCaller/#{payload.parent_type}/#{payload.caller_account_id}/#{payload.parent_app_id}/transport/allWeb",
              "TransportDuration/#{payload.parent_type}/#{payload.caller_account_id}/#{payload.parent_app_id}/transport/all",
              "TransportDuration/#{payload.parent_type}/#{payload.caller_account_id}/#{payload.parent_app_id}/transport/allWeb",
              "ErrorsByCaller/#{payload.parent_type}/#{payload.caller_account_id}/#{payload.parent_app_id}/transport/all",
              "ErrorsByCaller/#{payload.parent_type}/#{payload.caller_account_id}/#{payload.parent_app_id}/transport/allWeb",
              ["External/newrelic.com/Net::HTTP/GET", "test_txn2"]
            ]

            assert_metrics_recorded expected_metrics
          end
        end

        def test_segment_writes_outbound_request_headers
          request = RequestWrapper.new
          with_config cat_config do
            in_transaction :category => :controller do
              segment = Transaction.start_external_request_segment(
                library: "Net::HTTP",
                uri: "http://remotehost.com/blogs/index",
                procedure: "GET"
              )
              segment.add_request_headers request
              segment.finish
            end
          end
          assert request.headers.key?("X-NewRelic-ID"), "Expected to find X-NewRelic-ID header"
          assert request.headers.key?("X-NewRelic-Transaction"), "Expected to find X-NewRelic-Transaction header"
        end

        def test_segment_writes_synthetics_header_for_synthetics_txn
          request = RequestWrapper.new
          with_config cat_config do
            in_transaction :category => :controller do |txn|
              txn.raw_synthetics_header = json_dump_and_encode [1, 42, 100, 200, 300]
              segment = Transaction.start_external_request_segment(
                library: "Net::HTTP",
                uri: "http://remotehost.com/blogs/index",
                procedure: "GET"
              )
              segment.add_request_headers request
              segment.finish
            end
          end
          assert request.headers.key?("X-NewRelic-Synthetics"), "Expected to find X-NewRelic-Synthetics header"
        end

        def test_add_request_headers_renames_segment_based_on_host_header
          request = RequestWrapper.new({"host" => "anotherhost.local"})
          with_config cat_config do
            in_transaction :category => :controller do
              segment = Transaction.start_external_request_segment(
                library: "Net::HTTP",
                uri: "http://remotehost.com/blogs/index",
                procedure: "GET"
              )
              assert_equal "External/remotehost.com/Net::HTTP/GET", segment.name
              segment.add_request_headers request
              assert_equal "External/anotherhost.local/Net::HTTP/GET", segment.name
              segment.finish
            end
          end
        end

        def test_read_response_headers_decodes_valid_appdata
          response = {
            'X-NewRelic-App-Data' => make_app_data_payload("1#1884", "txn-name", 2, 8, 0, TRANSACTION_GUID)
          }

          with_config cat_config do
            in_transaction :category => :controller do |txn|
              segment = Transaction.start_external_request_segment(
                library: "Net::HTTP",
                uri: "http://remotehost.com/blogs/index",
                procedure: "GET"
              )
              segment.read_response_headers response
              segment.finish

              assert segment.cross_app_request?
              assert_equal "1#1884", segment.cross_process_id
              assert_equal "txn-name", segment.cross_process_transaction_name
              assert_equal "BEC1BC64675138B9", segment.transaction_guid
            end
          end
        end

        def test_read_response_headers_ignores_invalid_appdata
          response = {
            'X-NewRelic-App-Data' => "this#is#not#valid#appdata"
          }

          with_config cat_config do
            in_transaction :category => :controller do |txn|
              segment = Transaction.start_external_request_segment(
                library: "Net::HTTP",
                uri: "http://remotehost.com/blogs/index",
                procedure: "GET"
              )
              segment.read_response_headers response
              segment.finish

              refute segment.cross_app_request?
              assert_nil segment.cross_process_id
              assert_nil segment.cross_process_transaction_name
              assert_nil segment.transaction_guid
            end
          end
        end

        def test_read_response_headers_ignores_invalid_cross_app_id
          response = {
            'X-NewRelic-App-Data' => make_app_data_payload("not_an_ID", "txn-name", 2, 8, 0, TRANSACTION_GUID)
          }

          with_config cat_config do
            in_transaction :category => :controller do |txn|
              segment = Transaction.start_external_request_segment(
                library: "Net::HTTP",
                uri: "http://remotehost.com/blogs/index",
                procedure: "GET"
              )
              segment.read_response_headers response
              segment.finish

              refute segment.cross_app_request?
              assert_nil segment.cross_process_id
              assert_nil segment.cross_process_transaction_name
              assert_nil segment.transaction_guid
            end
          end
        end

        def test_uri_recorded_as_tt_attribute
          segment = nil
          uri = "http://newrelic.com/blogs/index"

          in_transaction :category => :controller do
            segment = Transaction.start_external_request_segment(
              library: "Net::HTTP",
              uri: uri,
              procedure: "GET"
            )
            segment.finish
          end

          sample = last_transaction_trace
          node = find_node_with_name(sample, segment.name)

          assert_equal uri, node.params[:uri]
        end

        def test_guid_recorded_as_tt_attribute_for_cat_txn
          segment = nil

          response = {
            'X-NewRelic-App-Data' => make_app_data_payload("1#1884", "txn-name", 2, 8, 0, TRANSACTION_GUID)
          }

          with_config cat_config do
            in_transaction :category => :controller do
              segment = Transaction.start_external_request_segment(
                library: "Net::HTTP",
                uri: "http://remotehost.com/blogs/index",
                procedure: "GET"
              )
              segment.read_response_headers response
              segment.finish
            end
          end

          sample = last_transaction_trace
          node = find_node_with_name(sample, segment.name)

          assert_equal TRANSACTION_GUID, node.params[:transaction_guid]
        end

        # --- get_request_metadata

        def test_get_request_metadata
          with_config cat_config.merge(:'cross_application_tracer.enabled' => true) do
            in_transaction do |txn|
              rmd = external_request_segment {|s| s.get_request_metadata}
              assert_instance_of String, rmd
              rmd = @obfuscator.deobfuscate rmd
              rmd = JSON.parse rmd
              assert_instance_of Hash, rmd

              assert_equal '269975#22824', rmd['NewRelicID']

              assert_instance_of Array, rmd['NewRelicTransaction']
              assert_equal txn.guid, rmd['NewRelicTransaction'][0]
              refute rmd['NewRelicTransaction'][1]

              assert_equal txn.cat_trip_id, rmd['NewRelicTransaction'][2]
              assert_equal txn.cat_path_hash, rmd['NewRelicTransaction'][3]

              refute rmd.key? 'NewRelicSynthetics'

              assert txn.state.is_cross_app_caller?
            end
          end
        end

        def test_get_request_metadata_with_cross_app_tracing_disabled
          with_config cat_config.merge(:'cross_application_tracer.enabled' => false) do
            in_transaction do |txn|
              rmd = external_request_segment {|s| s.get_request_metadata}
              refute rmd, "`get_request_metadata` should return nil with cross app tracing disabled"
            end
          end
        end

        def test_get_request_metadata_with_synthetics_header
          with_config cat_config do
            in_transaction do |txn|
              txn.raw_synthetics_header = 'raw_synth'

              rmd = external_request_segment {|s| s.get_request_metadata}

              rmd = @obfuscator.deobfuscate rmd
              rmd = JSON.parse rmd

              assert_equal 'raw_synth', rmd['NewRelicSynthetics']
            end
          end
        end

        def test_get_request_metadata_not_in_transaction
          with_config cat_config do
            refute external_request_segment {|s| s.get_request_metadata}
          end
        end

        # --- process_response_metadata

        def test_process_response_metadata
          with_config cat_config do
            in_transaction do |txn|

              rmd = @obfuscator.obfuscate ::JSON.dump({
                NewRelicAppData: [
                  NewRelic::Agent.config[:cross_process_id],
                  'Controller/root/index',
                  0.001,
                  0.5,
                  60,
                  txn.guid
                ]
              })

              segment = external_request_segment {|s| s.process_response_metadata rmd; s}
              assert_equal 'ExternalTransaction/example.com/269975#22824/Controller/root/index', segment.name
            end
          end
        end

        def test_process_response_metadata_not_in_transaction
          with_config cat_config do

            rmd = @obfuscator.obfuscate ::JSON.dump({
              NewRelicAppData: [
                NewRelic::Agent.config[:cross_process_id],
                'Controller/root/index',
                0.001,
                0.5,
                60,
                'abcdef'
              ]
            })

            segment = external_request_segment {|s| s.process_response_metadata rmd; s}
            assert_equal 'External/example.com/foo/get', segment.name
          end
        end

        def test_process_response_metadata_with_invalid_cross_app_id
          with_config cat_config do
            in_transaction do |txn|

              rmd = @obfuscator.obfuscate ::JSON.dump({
                NewRelicAppData: [
                  'bugz',
                  'Controller/root/index',
                  0.001,
                  0.5,
                  60,
                  txn.guid
                ]
              })

              segment = nil
              l = with_array_logger do
                segment = external_request_segment {|s| s.process_response_metadata rmd; s}
              end
              refute l.array.empty?, "process_response_metadata should log error on invalid ID"
              assert l.array.first =~ %r{invalid/non-trusted ID}

              assert_equal 'External/example.com/foo/get', segment.name
            end
          end
        end

        def test_process_response_metadata_with_untrusted_cross_app_id
          with_config cat_config do
            in_transaction do |txn|

              rmd = @obfuscator.obfuscate ::JSON.dump({
                NewRelicAppData: [
                  '190#666',
                  'Controller/root/index',
                  0.001,
                  0.5,
                  60,
                  txn.guid
                ]
              })

              segment = nil
              l = with_array_logger do
                segment = external_request_segment {|s| s.process_response_metadata rmd; s}
              end
              refute l.array.empty?, "process_response_metadata should log error on invalid ID"
              assert l.array.first =~ %r{invalid/non-trusted ID}

              assert_equal 'External/example.com/foo/get', segment.name
            end
          end
        end

        # ---

        def test_segment_adds_distributed_trace_header
          distributed_tracing_config = {
            :'distributed_tracing.enabled'      => true,
            :'cross_application_tracer.enabled' => false
          }

          with_config(distributed_tracing_config) do
            request = RequestWrapper.new
            with_config cat_config.merge(distributed_tracing_config) do
              in_transaction :category => :controller do |txn|
                segment = Transaction.start_external_request_segment(
                  library: "Net::HTTP",
                  uri: "http://remotehost.com/blogs/index",
                  procedure: "GET"
                )
                segment.add_request_headers request
                segment.finish
              end
            end
            assert request.headers.key?("X-NewRelic-Trace"), "Expected to find X-NewRelic-Trace header"
          end
        end

        def test_sets_start_time_from_api
          t = Time.now

          in_transaction do |txn|

            segment = Transaction.start_external_request_segment(
              library: "Net::HTTP",
              uri: "http://remotehost.com/blogs/index",
              procedure: "GET",
              start_time: t
            )
            segment.finish

            assert_equal t, segment.start_time
          end
        end

        def cat_config
          {
            :cross_process_id    => "269975#22824",
            :trusted_account_ids => [1,269975],
            :'cross_application_tracer.enabled' => true,
            :'distributed_tracing.enabled' => false,
          }
        end

        def make_app_data_payload( *args )
          @obfuscator.obfuscate( args.to_json ) + "\n"
        end

        def external_request_segment
          segment = NewRelic::Agent::Transaction.start_external_request_segment(
            library: :foo,
            uri: 'http://example.com/root/index',
            procedure: :get
          )
          v = yield segment
          segment.finish
          v
        end
      end
    end
  end
end
