# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'grpc'
require 'newrelic_rpm'

class GrpcServerTest < Minitest::Test
  include MultiverseHelpers

  def basic_grpc_desc
    ::GRPC::RpcDesc.new('type')
  end

  def basic_grpc_server
    ::GRPC::RpcServer.new
  end

  def host
    'thx'
  end

  def port
    '1138'
  end

  def method_name
    'hologram'
  end

  def metadata_hash
    {well: "I slipped on a T5 transfer this morning. It's never happened before."}
  end

  def method
    m = MiniTest::Mock.new
    m.expect(:original_name, method_name)
    m
  end

  def current_segment
    t = MiniTest::Mock.new
    t.expect(:add_agent_attribute, nil, [:'request.headers', {}])
    t.expect(:add_agent_attribute, nil, [:'request.uri', "grpc://:/"])
    t.expect(:add_agent_attribute, nil, [:'request.method', nil])
    t.expect(:add_agent_attribute, nil, [:'request.grpc_type', nil])
    t
  end

  def destinations
    NewRelic::Agent::Instrumentation::GRPC::Server::DESTINATIONS
  end

  def transaction
    t = MiniTest::Mock.new
    t.expect(:add_agent_attribute, nil, [:'request.headers', {}, destinations])
    t.expect(:add_agent_attribute, nil, [:'request.uri', "grpc://:/", destinations])
    t.expect(:add_agent_attribute, nil, [:'request.method', nil, destinations])
    t.expect(:add_agent_attribute, nil, [:'request.grpc_type', nil, destinations])
    t.expect(:current_segment, nil) # 4 existence checks
    t.expect(:current_segment, nil)
    t.expect(:current_segment, nil)
    t.expect(:current_segment, nil)
    t.expect(:current_segment, current_segment) # 4 attrs to add
    t.expect(:current_segment, current_segment)
    t.expect(:current_segment, current_segment)
    t.expect(:current_segment, current_segment)
    t.expect(:finish, nil)
    t
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

  def return_value
    'I like to remember things my own way.'
  end

  # shortcircuit out of #handle_with_tracing early (hit the first yield)
  def test_hosts_are_not_traced_if_on_the_denylist
    desc = basic_grpc_desc
    desc.instance_variable_set(:@trace_with_newrelic, false)

    new_transaction_called = false
    NewRelic::Agent::Transaction.stub(:start_new_transaction, proc { new_transaction_called = true }) do
      # by passing nil as the first argument, an exception will happen if the
      # code proceeds beyond the early return. this gives us confidence that the
      # early return is activated
      result = desc.handle_with_tracing(nil, nil, nil, nil) { return_value }
      assert_equal return_value, result
      refute new_transaction_called
    end
  end

  # make it all the way through #handle_with_tracing successfully (happy path)
  def test_request_is_handled_with_tracing
    desc = basic_grpc_desc
    def desc.trace_with_newrelic?; true; end # force a true response from this method
    def desc.process_distributed_tracing_headers(ac); end # noop this DT method (tested elsewhere)
    def desc.metadata_for_call(call); NewRelic::EMPTY_HASH; end # canned. test metadata_for_call elsewhere
    new_transaction_called = false
    NewRelic::Agent::Transaction.stub(:start_new_transaction, proc { new_transaction_called = true; transaction }) do
      # the 'active_call' and 'method' mocks used here will verify
      # (with expectations) to have methods called on them and return
      # appropriate responses
      result = desc.handle_with_tracing(nil, nil, method, nil) { return_value }
      assert_equal return_value, result
      assert new_transaction_called
    end
  end

  # make it all the way to the final yield in #handle_with_tracing, then
  # verify that raised exceptions are noticed
  def test_errors_from_handled_requests_are_noticed
    desc = basic_grpc_desc
    def desc.trace_with_newrelic?; true; end # force a true response from this method
    def desc.process_distributed_tracing_headers(ac); end # noop this DT method (tested elsewhere)
    def desc.metadata_for_call(call); NewRelic::EMPTY_HASH; end # canned. test metadata_for_call elsewhere
    raised_error = RuntimeError.new
    new_transaction_called = false
    NewRelic::Agent::Transaction.stub(:start_new_transaction, proc { new_transaction_called = true; transaction }) do
      received_error = nil
      notice_stub = proc { |e| received_error = e }
      NewRelic::Agent.stub(:notice_error, notice_stub) do
        assert_raises(RuntimeError) do
          result = desc.handle_with_tracing(nil, nil, method, nil) { raise raised_error }
        end
        assert_equal raised_error, received_error
        assert new_transaction_called
      end
    end
  end

  # in the #handle_with_tracing ensure block, make sure #finish isn't called
  # unless a segment was successfully created
  def test_do_not_call_finish_on_an_absent_segment
    desc = basic_grpc_desc
    def desc.trace_with_newrelic?; true; end # force a true response from this method
    def desc.process_distributed_tracing_headers(ac); end # noop this DT method (tested elsewhere)
    def desc.metadata_for_call(call); NewRelic::EMPTY_HASH; end # canned. test metadata_for_call elsewhere
    # force finishable to be nil
    NewRelic::Agent::Tracer.stub(:start_transaction_or_segment, nil) do
      result = desc.handle_with_tracing(nil, nil, method, nil) { return_value }
      assert_equal return_value, result
      # MiniTest does not have a wont_raise, but this test would fail if
      # finishable called #finish when nil
    end
  end

  def test_use_empty_metadata_if_an_active_call_is_absent
    desc = basic_grpc_desc
    assert_equal NewRelic::EMPTY_HASH, desc.send(:metadata_for_call, nil)
  end

  def test_use_empty_metadata_if_an_active_call_has_none
    desc = basic_grpc_desc
    active_call = MiniTest::Mock.new
    active_call.expect(:metadata, nil)
    assert_equal NewRelic::EMPTY_HASH, desc.send(:metadata_for_call, active_call)
  end

  def test_glean_metadata_from_an_active_call
    desc = basic_grpc_desc
    active_call = MiniTest::Mock.new
    active_call.expect(:metadata, metadata_hash)
    active_call.expect(:metadata, metadata_hash) # #metadata is called twice
    assert_equal metadata_hash, desc.send(:metadata_for_call, active_call)
  end

  def test_bypass_distributed_tracing_if_metadata_is_not_present
    desc = basic_grpc_desc
    # if the early return doesn't happen, #metadata will be called on nil
    # and error out
    refute desc.send(:process_distributed_tracing_headers, nil)
  end

  def test_bypass_distributed_tracing_if_metadata_is_empty
    desc = basic_grpc_desc
    bad_active_call = MiniTest::Mock.new
    bad_active_call.expect(:metadata, NewRelic::EMPTY_HASH)
    # if the early return doesn't happen, the bad_active_call mock will error
    # out when a second #metadata call is invoked upon it
    refute desc.send(:process_distributed_tracing_headers, nil)
  end

  def test_process_distributed_tracing_if_metadata_is_present
    desc = basic_grpc_desc
    received_args = nil
    dt_stub = proc { |hash, type| received_args = [hash, type] }
    NewRelic::Agent::DistributedTracing.stub(:accept_distributed_trace_headers, dt_stub) do
      desc.send(:process_distributed_tracing_headers, metadata_hash)
    end
    assert_equal [metadata_hash, 'Other'], received_args
  end

  def test_host_and_port_are_added_on_the_server_instance
    server = basic_grpc_server
    server.add_http2_port_with_tracing("#{host}:#{port}", :this_port_is_insecure) {}
    assert_equal(server.instance_variable_get(host_var), host)
    assert_equal(server.instance_variable_get(port_var), port)
  end

  def test_host_and_port_are_not_added_if_info_is_not_available
    server = basic_grpc_server
    server.add_http2_port_with_tracing('bogus_host', :this_port_is_insecure) {}
    refute_includes server.instance_variables, host_var
    refute_includes server.instance_variables, port_var
  end

  def test_host_and_port_and_method_are_added_on_the_desc
    server = basic_grpc_server
    server.instance_variable_set(host_var, host)
    server.instance_variable_set(port_var, port)
    desc = basic_grpc_desc
    server.instance_variable_set(:@rpc_descs, method_name => desc)
    server.run_with_tracing {}
    assert_equal desc.instance_variable_get(method_var), method_name
  end

  def test_host_and_port_from_host_string_when_string_is_valid
    results = basic_grpc_server.send(:host_and_port_from_host_string, "#{host}:#{port}")
    assert_equal [host, port], results
  end

  def test_host_and_port_from_host_string_when_string_is_nil
    results = basic_grpc_server.send(:host_and_port_from_host_string, nil)
    assert_nil results
  end

  def test_host_and_port_from_host_string_when_string_is_invalid
    results = basic_grpc_server.send(:host_and_port_from_host_string, 'string_without_a_colon')
    assert_nil results
  end

  def test_trace_with_newrelic_leverages_an_instance_var_set_to_true
    desc = basic_grpc_desc
    desc.instance_variable_set(:@trace_with_newrelic, true)
    assert desc.send(:trace_with_newrelic?)
  end

  def test_trace_with_newrelic_leverages_an_instance_var_set_to_false
    desc = basic_grpc_desc
    desc.instance_variable_set(:@trace_with_newrelic, false)
    refute desc.send(:trace_with_newrelic?)
  end

  def test_trace_with_newrelic_if_the_host_is_unknown
    desc = basic_grpc_desc
    assert desc.send(:trace_with_newrelic?)
  end

  def test_trace_with_newrelic_if_the_host_is_denylisted
    host = 'unwanted.host.net'
    unwanted_host_patterns = [/unwanted/]
    desc = basic_grpc_desc
    desc.instance_variable_set(host_var, host)
    mock = MiniTest::Mock.new
    mock.expect(:[], unwanted_host_patterns, [:'instrumentation.grpc.host_denylist'])
    NewRelic::Agent.stub(:config, mock) do
      refute desc.send(:trace_with_newrelic?)
    end
  end

  def test_trace_with_newrelic_if_the_host_is_not_denylisted
    host = 'unwanted.host.net'
    unwanted_host_patterns = [/unwanted/]
    desc = basic_grpc_desc
    desc.instance_variable_set(host_var, 'wanted.host.net')
    mock = MiniTest::Mock.new
    mock.expect(:[], unwanted_host_patterns, [:'instrumentation.grpc.host_denylist'])
    NewRelic::Agent.stub(:config, mock) do
      assert desc.send(:trace_with_newrelic?)
    end
  end

  def test_grpc_headers_exclude_dt_headers
    expected = {our: :blues,
                hometown: :cha_cha_cha,
                itaewon: :class}
    input = NewRelic::Agent::Instrumentation::GRPC::Server::DT_KEYS.each_with_object(expected.dup) do |key, hash|
      hash[key] = true
    end
    assert_equal (expected.keys.size + NewRelic::Agent::Instrumentation::GRPC::Server::DT_KEYS.size), input.keys.size
    assert_equal expected, basic_grpc_desc.send(:grpc_headers, input)
  end

  def test_trace_options
    desc = basic_grpc_desc
    desc.instance_variable_set(NewRelic::Agent::Instrumentation::GRPC::Server::INSTANCE_VAR_METHOD, method_name)
    expected = {category: NewRelic::Agent::Instrumentation::GRPC::Server::CATEGORY,
                transaction_name: "Controller/#{method_name}"}
    assert_equal expected, desc.send(:trace_options)
  end

  def test_grpc_params
    desc = basic_grpc_desc
    type = 'congrats smarty pants'
    desc.instance_variable_set(NewRelic::Agent::Instrumentation::GRPC::Server::INSTANCE_VAR_METHOD, method_name)
    desc.instance_variable_set(NewRelic::Agent::Instrumentation::GRPC::Server::INSTANCE_VAR_HOST, host)
    desc.instance_variable_set(NewRelic::Agent::Instrumentation::GRPC::Server::INSTANCE_VAR_PORT, port)
    def desc.grpc_headers(metadata); 'canned_headers'; end
    expected = {'request.headers': 'canned_headers',
                'request.uri': "grpc://#{host}:#{port}/#{method_name}",
                'request.method': method_name,
                'request.grpc_type': type}
    result = desc.send(:grpc_params, metadata_hash, type)
    assert_equal expected, result
  end
end
