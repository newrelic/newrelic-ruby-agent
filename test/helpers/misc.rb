# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

def default_service(stubbed_method_overrides = {})
  service = stub
  stubbed_method_defaults = {
    :connect => {},
    :shutdown => nil,
    :agent_id= => nil,
    :agent_id => nil,
    :collector => stub_everything,
    :request_timeout= =>  nil,
    :metric_data => nil,
    :error_data => nil,
    :transaction_sample_data => nil,
    :sql_trace_data => nil,
    :get_agent_commands => [],
    :agent_command_results => nil,
    :analytic_event_data => nil,
    :valid_to_marshal? => true
  }

  service.stubs(stubbed_method_defaults.merge(stubbed_method_overrides))

  # When session gets called yield to the given block.
  service.stubs(:session).yields
  service
end

def fixture_tcp_socket( response )
  # Don't actually talk to Google.
  socket = stub("socket").tap do |s|
    s.stubs(:closed?).returns(false)
    s.stubs(:close)
    s.stubs(:setsockopt)

    # Simulate a bunch of socket-ey stuff since Mocha doesn't really
    # provide any other way to do it

    stubs(:sysread) do |size, buf=''|
      @data ||= response.to_s
      raise EOFError if @data.empty?
      buf.replace @data.slice!(0, size)
      buf
    end

    stubs(:check_write) { self.write_checker = Proc.new }
    stubs(:write) do |buf|
      self.write_checker.call(buf) if self.write_checker
      buf.length
    end

    class << self
      attr_accessor :response, :write_checker
      alias_method :read_nonblock, :sysread
    end
  end

  socket.stubs(:response).returns(response)
  TCPSocket.stubs(:open).returns(socket)

  return socket
end

def dummy_mysql_explain_result(hash=nil)
  hash ||= {
    'Id' => '1',
    'Select Type' => 'SIMPLE',
    'Table' => 'sandwiches',
    'Type' => 'range',
    'Possible Keys' => 'PRIMARY',
    'Key' => 'PRIMARY',
    'Key Length' => '4',
    'Ref' => '',
    'Rows' => '1',
    'Extra' => 'Using index'
  }
  explain_result = mock('explain result')
  explain_result.stubs(:each_hash).yields(hash)
  explain_result
end

def symbolize_keys_in_object(object)
  case object
  when Hash
   object.inject({}) do |memo, (k, v)|
      memo[k.to_sym] = symbolize_keys_in_object(v)
      memo
    end
  when Array
    object.map {|o| symbolize_keys_in_object(o)}
  else
    object
  end
end

def stringify_keys_in_object(object)
  case object
  when Hash
   object.inject({}) do |memo, (k, v)|
      memo[k.to_s] = stringify_keys_in_object(v)
      memo
    end
  when Array
    object.map {|o| stringify_keys_in_object(o)}
  else
    object
  end
end
