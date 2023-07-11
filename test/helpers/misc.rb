# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

def default_service(stubbed_method_overrides = {})
  service = stub
  stubbed_method_defaults = {
    :connect => {},
    :shutdown => nil,
    :agent_id= => nil,
    :agent_id => nil,
    :collector => stub_everything,
    :request_timeout= => nil,
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

def fixture_tcp_socket(response)
  # Don't actually talk to Google.
  socket = stub('socket').tap do |s|
    s.stubs(:closed?).returns(false)
    s.stubs(:close)
    s.stubs(:setsockopt)

    # Simulate a bunch of socket-ey stuff since Mocha doesn't really
    # provide any other way to do it

    stubs(:sysread) do |size, buf = ''|
      @data ||= response.to_s
      raise EOFError if @data.empty?

      buf.replace(@data.slice!(0, size))
      buf
    end

    stubs(:check_write) { self.write_checker = Proc.new }
    stubs(:write) do |buf|
      self.write_checker&.call(buf)
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

def dummy_mysql_explain_result(hash = nil)
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
    object.map { |o| symbolize_keys_in_object(o) }
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
    object.map { |o| stringify_keys_in_object(o) }
  else
    object
  end
end

def wait_until_not_nil(give_up_after = 3, &block)
  total_tries = give_up_after * 10
  current_tries = 0
  while yield.nil? and current_tries < total_tries
    sleep(0.1)
    current_tries += 1
  end
end

def skip_unless_minitest5_or_above
  return if defined?(MiniTest::VERSION) && MiniTest::VERSION > '5'

  skip 'This test requires MiniTest v5+'
end

def skip_unless_ci_cron
  return if ENV['CI_CRON']

  skip 'This test only runs as part of the CI cron workflow'
end

def agent_root
  @agent_root ||= File.expand_path('../../..', __FILE__).freeze
end

def newest_ruby
  @newest_ruby ||= begin
    hash = YAML.load_file(File.join(agent_root, '.github/workflows/ci_cron.yml'))
    version_string = hash['jobs']['unit_tests']['strategy']['matrix']['ruby-version'].sort do |a, b|
      Gem::Version.new(a) <=> Gem::Version.new(b)
    end.last
    Gem::Version.new(version_string)
  end
end

def skip_unless_newest_ruby
  return if Gem::Version.new(RUBY_VERSION) >= newest_ruby

  skip 'This test only runs on the latest CI cron Ruby version'
end
