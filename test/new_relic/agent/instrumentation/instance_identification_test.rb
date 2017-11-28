# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/instrumentation/active_record_helper'

module NewRelic
  module Agent
    module Instrumentation
      module ActiveRecordHelper
        class InstanceIdentificationTest < Minitest::Test

          def test_for_constructs_id_with_configured_host_and_port
            config = {
              :host => "jonan.local",
              :port => 42
            }

            host = InstanceIdentification.host(config)
            ppid = InstanceIdentification.port_path_or_id(config)

            assert_equal "jonan.local", host
            assert_equal "42", ppid
          end

          def test_for_constructs_id_with_unspecified_configuration
            config = {}
            host = InstanceIdentification.host(config)
            ppid = InstanceIdentification.port_path_or_id(config)

            assert_equal "localhost", host
            assert_equal "default", ppid
          end

          def test_for_constructs_id_with_weird_configs
            config = {
              :host => "",
              :port => ""
            }

            host = InstanceIdentification.host(config)
            ppid = InstanceIdentification.port_path_or_id(config)

            assert_equal "unknown", host
            assert_equal "unknown", ppid
          end

          def test_for_constructs_id_with_configured_host_without_port
            config = { :host => "jonan.gummy_planet" }

            host = InstanceIdentification.host(config)
            ppid = InstanceIdentification.port_path_or_id(config)

            assert_equal "jonan.gummy_planet", host
            assert_equal "default", ppid
          end

          def test_for_constructs_id_with_port_without_host
            config = { :port => 1337 }

            host = InstanceIdentification.host(config)
            ppid = InstanceIdentification.port_path_or_id(config)

            assert_equal "localhost", host
            assert_equal "1337", ppid
          end

          def test_for_constructs_id_with_default_port
            config = {
              :adapter => "mysql",
              :host => "jonan.gummy_planet"
            }

            host = InstanceIdentification.host(config)
            ppid = InstanceIdentification.port_path_or_id(config)

            assert_equal "jonan.gummy_planet", host
            assert_equal "3306", ppid
          end

          def test_for_constructs_id_with_postgres_directory
            config = {
              :adapter => "postgresql",
              :host => "/tmp"
            }

            host = InstanceIdentification.host(config)
            ppid = InstanceIdentification.port_path_or_id(config)

            assert_equal "localhost", host
            assert_equal "default", ppid
          end

          def test_for_constructs_id_with_mysql_socket
            %w[ mysql mysql2 jdbcmysql ].each do |adapter|
              config = {
                :adapter => adapter,
                :socket => "/var/run/mysqld.sock"
              }

              host = InstanceIdentification.host(config)
              ppid = InstanceIdentification.port_path_or_id(config)

              assert_equal "localhost", host
              assert_equal "/var/run/mysqld.sock", ppid
            end
          end

          def test_supports_supported_adapters
            %w(mysql mysql2 postgresql).each do |adapter|
              assert InstanceIdentification.supported_adapter?({:adapter => adapter })
            end
          end

          SUPPORTED_PRODUCTS = ["Postgres", "MySQL"]

          load_cross_agent_test('datastores/datastore_instances').each do |test|
            next unless SUPPORTED_PRODUCTS.include?(test['product'])

            define_method :"test_#{test['name'].tr(' ', '_')}" do
              NewRelic::Agent.drop_buffered_data
              NewRelic::Agent::Hostname.stubs(:get).returns(test['system_hostname'])

              in_transaction do
                config = convert_test_case_to_config test
                product, operation, collection = ActiveRecordHelper.product_operation_collection_for "Blog Find", nil , config[:adapter]
                host = ActiveRecordHelper::InstanceIdentification.host(config)
                port_path_or_id = ActiveRecordHelper::InstanceIdentification.port_path_or_id(config)

                segment = NewRelic::Agent::Transaction.start_datastore_segment(
                  product: product,
                  operation: operation,
                  collection: collection,
                  host: host,
                  port_path_or_id: port_path_or_id
                )
                segment.finish
              end

              assert_metrics_recorded test['expected_instance_metric']
            end
          end

          CONFIG_NAMES = {
            "db_hostname" => :host,
            "unix_socket" => :socket,
            "port" => :port,
            "product" => :adapter
          }

          def convert_test_case_to_config test_case
            config = test_case.inject({}) do |memo, (k,v)|
              if config_key = CONFIG_NAMES[k]
                memo[config_key] = v
              end
              memo
            end
            convert_product_to_adapter config
            config
          end

          PRODUCT_TO_ADAPTER_NAMES = {
            "Postgres" => "postgresql",
            "MySQL" => "mysql",
            "SQLite" => "sqlite3"
          }

          def convert_product_to_adapter config
            config[:adapter] = PRODUCT_TO_ADAPTER_NAMES[config[:adapter]]
          end
        end
      end
    end
  end
end
