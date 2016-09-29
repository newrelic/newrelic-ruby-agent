# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/instrumentation/active_record_helper'

module NewRelic
  module Agent
    module Instrumentation
      module ActiveRecordHelper
        class InstanceIdentifierTest < Minitest::Test

          def test_for_constructs_id_with_configured_host_and_port
            config = {
              :host => "jonan.local",
              :port => 42
            }

            assert_equal "jonan.local:42", InstanceIdentifier.for(config)
          end

          def test_for_constructs_id_with_unspecified_configuration
            NewRelic::Agent::Hostname.stubs(:get).returns("jonan.pizza_cube")

            assert_equal "jonan.pizza_cube:default", InstanceIdentifier.for({})
          end

          def test_for_constructs_id_with_weird_configs
            config = {
              :host => "",
              :port => ""
            }
            NewRelic::Agent::Hostname.stubs(:get).returns("jonan.pizza_cube")

            assert_equal "jonan.pizza_cube:unknown", InstanceIdentifier.for(config)
          end

          def test_for_constructs_id_with_configured_host_without_port
            config = { :host => "jonan.gummy_planet" }

            assert_equal "jonan.gummy_planet:default", InstanceIdentifier.for(config)
          end

          def test_for_constructs_id_with_port_without_host
            NewRelic::Agent::Hostname.stubs(:get).returns("jonan.pizza_cube")
            config = { :port => 1337 }

            assert_equal "jonan.pizza_cube:1337", InstanceIdentifier.for(config)
          end

          def test_for_constructs_id_with_detected_localhost
            NewRelic::Agent::Hostname.stubs(:get).returns("jonan.pizza_cube")

            %w[localhost 0.0.0.0 127.0.0.1 0:0:0:0:0:0:0:1 0:0:0:0:0:0:0:0 ::1 ::].each do |host|
              config = { :host => host }

              assert_equal "jonan.pizza_cube:default", InstanceIdentifier.for(config)
            end
          end

          def test_for_constructs_id_with_default_port
            config = {
              :adapter => "mysql",
              :host => "jonan.gummy_planet"
            }

            assert_equal "jonan.gummy_planet:3306", InstanceIdentifier.for(config)
          end

          def test_for_constructs_id_with_postgres_directory
            NewRelic::Agent::Hostname.stubs(:get).returns("jonan.pizza_cube")
            config = {
              :adapter => "postgresql",
              :host => "/tmp"
            }

            assert_equal "jonan.pizza_cube:default", InstanceIdentifier.for(config)
          end

          def test_for_constructs_id_with_mysql_socket
            NewRelic::Agent::Hostname.stubs(:get).returns("jonan.pizza_cube")
            %w[ mysql mysql2 jdbcmysql ].each do |adapter|
              config = {
                :adapter => adapter,
                :socket => "/var/run/mysqld.sock"
              }

              assert_equal "jonan.pizza_cube:/var/run/mysqld.sock", InstanceIdentifier.for(config)
            end
          end

        end
      end
    end
  end
end
