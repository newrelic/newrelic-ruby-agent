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
            ppid = InstanceIdentification.path_port_or_id(config)

            assert_equal "jonan.local", host
            assert_equal "42", ppid
          end

          def test_for_constructs_id_with_unspecified_configuration
            NewRelic::Agent::Hostname.stubs(:get).returns("jonan.pizza_cube")
            config = {}
            host = InstanceIdentification.host(config)
            ppid = InstanceIdentification.path_port_or_id(config)

            assert_equal "jonan.pizza_cube", host
            assert_equal "default", ppid
          end

          def test_for_constructs_id_with_weird_configs
            config = {
              :host => "",
              :port => ""
            }

            host = InstanceIdentification.host(config)
            ppid = InstanceIdentification.path_port_or_id(config)

            assert_equal "unknown", host
            assert_equal "unknown", ppid
          end

          def test_for_constructs_id_with_configured_host_without_port
            config = { :host => "jonan.gummy_planet" }

            host = InstanceIdentification.host(config)
            ppid = InstanceIdentification.path_port_or_id(config)

            assert_equal "jonan.gummy_planet", host
            assert_equal "default", ppid
          end

          def test_for_constructs_id_with_port_without_host
            NewRelic::Agent::Hostname.stubs(:get).returns("jonan.pizza_cube")
            config = { :port => 1337 }

            host = InstanceIdentification.host(config)
            ppid = InstanceIdentification.path_port_or_id(config)

            assert_equal "jonan.pizza_cube", host
            assert_equal "1337", ppid
          end

          def test_for_constructs_id_with_detected_localhost
            NewRelic::Agent::Hostname.stubs(:get).returns("jonan.pizza_cube")

            %w[localhost 0.0.0.0 127.0.0.1 0:0:0:0:0:0:0:1 0:0:0:0:0:0:0:0 ::1 ::].each do |host|
              config = { :host => host }

              host = InstanceIdentification.host(config)
              ppid = InstanceIdentification.path_port_or_id(config)

              assert_equal "jonan.pizza_cube", host
              assert_equal "default", ppid
            end
          end

          def test_for_constructs_id_with_default_port
            config = {
              :adapter => "mysql",
              :host => "jonan.gummy_planet"
            }

            host = InstanceIdentification.host(config)
            ppid = InstanceIdentification.path_port_or_id(config)

            assert_equal "jonan.gummy_planet", host
            assert_equal "3306", ppid
          end

          def test_for_constructs_id_with_postgres_directory
            NewRelic::Agent::Hostname.stubs(:get).returns("jonan.pizza_cube")
            config = {
              :adapter => "postgresql",
              :host => "/tmp"
            }

            host = InstanceIdentification.host(config)
            ppid = InstanceIdentification.path_port_or_id(config)

            assert_equal "jonan.pizza_cube", host
            assert_equal "default", ppid
          end

          def test_for_constructs_id_with_mysql_socket
            NewRelic::Agent::Hostname.stubs(:get).returns("jonan.pizza_cube")
            %w[ mysql mysql2 jdbcmysql ].each do |adapter|
              config = {
                :adapter => adapter,
                :socket => "/var/run/mysqld.sock"
              }

              host = InstanceIdentification.host(config)
              ppid = InstanceIdentification.path_port_or_id(config)

              assert_equal "jonan.pizza_cube", host
              assert_equal "/var/run/mysqld.sock", ppid
            end
          end
        end
      end
    end
  end
end
