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
            segment = Transaction.start_external_request_segment "Net::HTTP", "http://remotehost.com/blogs/index", "GET"
            segment.finish
          end

          expected_metrics = [
            "External/remotehost.com/Net::HTTP/GET",
            "External/all",
            "External/remotehost.com/all",
            "External/allWeb",
            ["External/remotehost.com/Net::HTTP/GET", "test"]
          ]

          assert_metrics_recorded expected_metrics
        end

        def test_segment_records_noncat_metrics_when_cat_disabled
          request = RequestWrapper.new
          response = {
            'X-NewRelic-App-Data' => make_app_data_payload("1#1884", "txn-name", 2, 8, 0, TRANSACTION_GUID)
          }

          with_config(cat_config.merge({:"cross_application_tracer.enabled" => false})) do
            in_transaction "test", :category => :controller do
              segment = Transaction.start_external_request_segment "Net::HTTP", "http://remotehost.com/blogs/index", "GET"
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

          assert_metrics_recorded expected_metrics
        end

        def test_segment_records_noncat_metrics_without_valid_cross_process_id
          request = RequestWrapper.new
          response = {
            'X-NewRelic-App-Data' => make_app_data_payload("1#1884", "txn-name", 2, 8, 0, TRANSACTION_GUID)
          }

          with_config(cat_config.merge({:cross_process_id => ''})) do
            in_transaction "test", :category => :controller do
              segment = Transaction.start_external_request_segment "Net::HTTP", "http://remotehost.com/blogs/index", "GET"
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
              segment = Transaction.start_external_request_segment "Net::HTTP", "http://remotehost.com/blogs/index", "GET"
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

          assert_metrics_recorded expected_metrics
        end

        def test_segment_records_expected_metrics_for_cat_transaction
          response = {
            'X-NewRelic-App-Data' => make_app_data_payload("1#1884", "txn-name", 2, 8, 0, TRANSACTION_GUID)
          }

          with_config cat_config do
            in_transaction "test", :category => :controller do |txn|
              segment = Transaction.start_external_request_segment "Net::HTTP", "http://newrelic.com/blogs/index", "GET"
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

          assert_metrics_recorded expected_metrics
        end

        def test_segment_writes_outbound_request_headers
          request = RequestWrapper.new
          with_config cat_config do
            in_transaction :category => :controller do
              segment = Transaction.start_external_request_segment "Net::HTTP", "http://remotehost.com/blogs/index", "GET"
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
              segment = Transaction.start_external_request_segment "Net::HTTP", "http://remotehost.com/blogs/index", "GET"
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
              segment = Transaction.start_external_request_segment "Net::HTTP", "http://remotehost.com/blogs/index", "GET"
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
              segment = Transaction.start_external_request_segment "Net::HTTP", "http://remotehost.com/blogs/index", "GET"
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
              segment = Transaction.start_external_request_segment "Net::HTTP", "http://remotehost.com/blogs/index", "GET"
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
              segment = Transaction.start_external_request_segment "Net::HTTP", "http://remotehost.com/blogs/index", "GET"
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
            segment = Transaction.start_external_request_segment "Net::HTTP", uri, "GET"
            segment.finish
          end

          sample = NewRelic::Agent.agent.transaction_sampler.last_sample
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
              segment = Transaction.start_external_request_segment "Net::HTTP", "http://newrelic.com/blogs/index", "GET"
              segment.read_response_headers response
              segment.finish
            end
          end

          sample = NewRelic::Agent.agent.transaction_sampler.last_sample
          node = find_node_with_name(sample, segment.name)

          assert_equal TRANSACTION_GUID, node.params[:transaction_guid]
        end

        # --- get_request_metadata

        def test_get_request_metadata
          with_config cat_config do
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

        # --- process_request_metadata

        def test_process_request_metadata
          rmd = @obfuscator.obfuscate ::JSON.dump({
            NewRelicID: cat_config[:cross_process_id],
            NewRelicTransaction: ['abc', false, 'def', 'ghi']
          })

          in_transaction do |txn|
            external_request_segment {|s| s.process_request_metadata rmd}

            assert_equal cat_config[:cross_process_id], txn.state.client_cross_app_id
            assert_equal ['abc', false, 'def', 'ghi'], txn.state.referring_transaction_info
          end
        end

        def test_process_request_metadata_with_synthetics
          raw_synth = @obfuscator.obfuscate ::JSON.dump('raw_synth')

          rmd = @obfuscator.obfuscate ::JSON.dump({
            NewRelicID: cat_config[:cross_process_id],
            NewRelicTransaction: ['abc', false, 'def', 'ghi'],
            NewRelicSynthetics: 'raw_synth'
          })

          in_transaction do |txn|
            external_request_segment {|s| s.process_request_metadata rmd}

            assert_equal raw_synth, txn.raw_synthetics_header
            assert_equal 'raw_synth', txn.synthetics_payload
          end
        end

        def test_process_request_metadata_not_in_transaction
          rmd = @obfuscator.obfuscate ::JSON.dump({
            NewRelicID: cat_config[:cross_process_id],
            NewRelicTransaction: ['abc', false, 'def', 'ghi'],
            NewRelicSynthetics: 'raw_synth'
          })

          external_request_segment {|s| s.process_request_metadata rmd}
          state = NewRelic::Agent::TransactionState.tl_get
          refute state.client_cross_app_id
          refute state.referring_transaction_info
          refute state.current_transaction
        end

        # --- get_response_metadata

        def test_get_response_metadata
          with_config cat_config do
            in_transaction do |txn|
              rmd = external_request_segment {|s| s.get_response_metadata}
              assert_instance_of String, rmd
              rmd = @obfuscator.deobfuscate rmd
              rmd = JSON.parse rmd
              assert_instance_of Hash, rmd
              assert_instance_of Array, rmd['NewRelicAppData']

              assert_equal '269975#22824', rmd['NewRelicAppData'][0]
              assert_equal 'dummy', rmd['NewRelicAppData'][1]
              assert_instance_of Float, rmd['NewRelicAppData'][2]
              assert_instance_of Float, rmd['NewRelicAppData'][3]
              assert_equal -1, rmd['NewRelicAppData'][4]
              assert_equal txn.state.request_guid, rmd['NewRelicAppData'][5]
            end
          end
        end

        def test_get_response_metadata_not_in_transaction
          with_config cat_config do
            refute external_request_segment {|s| s.get_response_metadata}
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

        # ---

        def cat_config
          {
            :cross_process_id    => "269975#22824",
            :trusted_account_ids => [1,269975]
          }
        end

        def make_app_data_payload( *args )
          @obfuscator.obfuscate( args.to_json ) + "\n"
        end

        def external_request_segment
          segment = NewRelic::Agent::Transaction.start_external_request_segment :foo, 'http://example.com/root/index', :get
          v = yield segment
          segment.finish
          v
        end
      end
    end
  end
end
