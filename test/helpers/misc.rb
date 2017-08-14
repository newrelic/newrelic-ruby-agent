# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

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
  socket = stub("socket") do
    stubs(:closed?).returns(false)
    stubs(:close)
    stubs(:setsockopt)

    # Simulate a bunch of socket-ey stuff since Mocha doesn't really
    # provide any other way to do it
    class << self
      attr_accessor :response, :write_checker
    end

    def self.check_write
      self.write_checker = Proc.new
    end

    def self.write( buf )
      self.write_checker.call( buf ) if self.write_checker
      buf.length
    end

    def self.sysread( size, buf='' )
      @data ||= response.to_s
      raise EOFError if @data.empty?
      buf.replace @data.slice!( 0, size )
      buf
    end
    class << self
      alias_method :read_nonblock, :sysread
    end

  end

  socket.response = response
  TCPSocket.stubs( :open ).returns( socket )

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
