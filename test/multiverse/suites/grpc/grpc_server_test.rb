# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'grpc'
require 'newrelic_rpm'

class GrpcServerTest < Minitest::Test
  include MultiverseHelpers

  def basic_grpc_desc
    ::GRPC::RpcDesc
  end

  def basic_grpc_server
    ::GRPC::RpcServer
  end

  def host
    'thx'
  end

  def port
    1138
  end

  def method
    'hologram'
  end

  def host_var
    ::NewRelic::Agent::Instrumentation::GRPC::Server::INSTANCE_VAR_HOST
  end

  def port_var
    ::NewRelic::Agent::Instrumentation::GRPC::Server::INSTANCE_VAR_PORT
  end

  def method_var
    ::NewRelic::Agent::Instrumentation::GRPC::Server::INSTANCE_VAR_METHOD
  end

  # def test_hosts_are_not_traced_if_on_the_denylist
  #   return_value = 'I like to remember things my own way.'
  #   desc = basic_grpc_desc
  #   desc.instance_variable_set(:@trace_with_newrelic, false)
  #   in_transaction('grpc test') do |txn|
  #     # by passing nil as the first argument, an exception will happen if the
  #     # code proceeds beyond the early return. this gives us confidence that the
  #     # early return is activated
  #     result = desc.handle_with_tracing(nil, nil, nil) { return_value }
  #     assert_equal return_value, result
  #     # in_transaction always creates one segment, we don't want a second
  #     # segment when an early return is invoked
  #     assert_equal 1, txn.segments.count
  #   end
  # end

  # def test_host_and_port_are_added_on_the_server_instance
  #   server = basic_grpc_server
  #   basic_grpc_server.add_http2_port_with_tracing("#{host}:#{port}")
  #   assert_equal(server.instance_variable_get(host_var), host)
  #   assert_equal(server.instance_variable_get(port_var), port)
  # end

  # def test_host_and_port_and_method_are_added_on_the_desc
  #   server = basic_grpc_server
  #   server.instance_variable_set(host_var, host)
  #   server.instance_variable_set(port_var, port)
  #   desc = MiniTest::Mock.new
  #   desc.expect(:instance_variable_get, host, [host_var])
  #   desc.expect(:instance_variable_set, nil, [host_var, host])
  #   desc.expect(:instance_variable_get, port, [port_var])
  #   desc.expect(:instance_variable_set, nil, [port_var, port])
  #   desc.expect(:instance_variable_set, nil, [method_var, method])
  #   descs = [{method => desc}]
  #   Grpc::RpcServer.stub(:set_host_and_port_and_method_info_on_desc, descs) do
  #     server.run_with_tracing
  #     assert_equal desc.instance_variable_get(method_var), method
  #   end
  # end

  def test_host_and_port_from_host_string_when_string_is_valid
  end

  def test_host_and_port_from_host_string_when_string_is_nil
  end

  def test_host_and_port_from_host_string_when_string_is_invalid
  end
end
