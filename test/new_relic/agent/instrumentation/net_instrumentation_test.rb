#!/usr/bin/env ruby
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.


require 'net/http'
require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/cross_app_tracing'

# Add some stuff to Net::HTTP::HTTPResponse to facilitate building response data
class Net::HTTPResponse
  def to_s
    buf = ''
    buf << "HTTP/%s %d %s\r\n" % [ self.http_version, self.code, self.message ]
    self.each_capitalized {|k,v| buf << k << ': ' << v << "\r\n" }
    buf << "\r\n"
    buf << @body if @body
    return buf
  end
  def initialize_copy( original )
    @http_version = @http_version.dup
    @code         = @code.dup
    @message      = @message.dup
    @body         = @body.dup
    @read         = false
    @header       = @header.dup
  end

  unless instance_methods.map {|name| name.to_sym }.include?( :body= )
    def body=( newbody )
      @body = newbody
    end
  end
end

class NewRelic::Agent::Instrumentation::NetInstrumentationTest < Test::Unit::TestCase
  include NewRelic::Agent::Instrumentation::ControllerInstrumentation,
          NewRelic::Agent::CrossAppMonitor::EncodingFunctions,
          NewRelic::Agent::CrossAppTracing

  CANNED_RESPONSE = Net::HTTPOK.new( '1.1', '200', 'OK' )
  CANNED_RESPONSE.body = 
    '<html><head><title>Canned Response</title></head><body>Canned response.</body></html>'
  CANNED_RESPONSE['content-type'] = 'text/html; charset=UTF-8'
  CANNED_RESPONSE['date'] = 'Tue, 29 Jan 2013 21:52:04 GMT'
  CANNED_RESPONSE['expires'] = '-1'
  CANNED_RESPONSE['server'] = 'gws'
  CANNED_RESPONSE.freeze

  TRANSACTION_GUID = 'BEC1BC64675138B9'


  def setup
    NewRelic::Agent.manual_start(
      :"cross_application_tracer.enabled" => false,
      :"transaction_tracer.enabled"       => true,
      :cross_process_id                   => '269975#22824',
      :encoding_key                       => 'gringletoes'
    )

    # $stderr.puts '', '---', ''
    # NewRelic::Agent.logger = NewRelic::Agent::AgentLogger.new( {:log_level => 'debug'}, '', Logger.new($stderr) )

    @engine = NewRelic::Agent.instance.stats_engine
    @engine.clear_stats

    @engine.start_transaction( 'test' )
    NewRelic::Agent::TransactionInfo.get.guid = TRANSACTION_GUID

    @sampler = NewRelic::Agent.instance.transaction_sampler
    @sampler.notice_first_scope_push( Time.now.to_f )
    @sampler.notice_transaction( '/path', '/path', {} )
    @sampler.notice_push_scope "Controller/sandwiches/index"
    @sampler.notice_sql("SELECT * FROM sandwiches WHERE bread = 'wheat'", nil, 0)
    @sampler.notice_push_scope "ab"
    @sampler.notice_sql("SELECT * FROM sandwiches WHERE bread = 'white'", nil, 0)
    @sampler.notice_push_scope "fetch_external_service"

    @response = CANNED_RESPONSE.clone
    @socket = fixture_tcp_socket( @response )
  end

  def teardown
    NewRelic::Agent.instance.transaction_sampler.reset!
    Thread::current[:newrelic_scope_stack] = nil
    NewRelic::Agent.instance.stats_engine.end_transaction
  end


  #
  # Helpers
  #

  def fixture_tcp_socket( response )

    # Don't actually talk to Google.
    socket = stub("socket") do
      stubs(:closed?).returns(false)
      stubs(:close)

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


  def make_app_data_payload( *args )
    return obfuscate_with_key( 'gringletoes', args.to_json ).gsub( /\n/, '' ) + "\n"
  end


  def find_last_segment
    builder = NewRelic::Agent.agent.transaction_sampler.builder
    last_segment = nil
    builder.current_segment.each_segment {|s| last_segment = s }

    return last_segment
  end



  #
  # Tests
  #

  def test_get
    url = URI.parse('http://www.google.com/index.html')
    res = Net::HTTP.start(url.host, url.port) {|http|
      http.get('/index.html')
    }
      
    assert_match %r/<head>/i, res.body
    assert_includes @engine.metrics, 'External/all'
    assert_includes @engine.metrics, 'External/www.google.com/Net::HTTP/GET'
    assert_includes @engine.metrics, 'External/allOther'
    assert_includes @engine.metrics, 'External/www.google.com/all'

    assert_not_includes @engine.metrics, 'External/allWeb'
  end

  def test_background
    res = nil

    perform_action_with_newrelic_trace("task", :category => :task) do
      url = URI.parse('http://www.google.com/index.html')
      res = Net::HTTP.start(url.host, url.port) {|http|
        http.get('/index.html')
      }
    end

    assert_match %r/<head>/i, res.body

    assert_includes @engine.metrics, 'External/all'
    assert_includes @engine.metrics, 'External/www.google.com/Net::HTTP/GET'
    assert_includes @engine.metrics, 'External/allOther'
    assert_includes @engine.metrics, 'External/www.google.com/all'
    assert_includes @engine.metrics,
      'OtherTransaction/Background/NewRelic::Agent::Instrumentation::NetInstrumentationTest/task'

    assert_not_includes @engine.metrics, 'External/allWeb'
  end

  def test_transactional
    res = nil

    perform_action_with_newrelic_trace("task") do
      url = URI.parse('http://www.google.com/index.html')
      res = Net::HTTP.start(url.host, url.port) {|http|
        http.get('/index.html')
      }
    end

    assert_match %r/<head>/i, res.body

    assert_includes @engine.metrics, 'External/all'
    assert_includes @engine.metrics, 'External/www.google.com/Net::HTTP/GET'
    assert_includes @engine.metrics, 'External/allWeb'
    assert_includes @engine.metrics, 'External/www.google.com/all'
    assert_includes @engine.metrics,
      'Controller/NewRelic::Agent::Instrumentation::NetInstrumentationTest/task'

    assert_not_includes @engine.metrics, 'External/allOther'
  end

  def test_get__simple
    Net::HTTP.get URI.parse('http://www.google.com/index.html')

    assert_includes @engine.metrics, 'External/all'
    assert_includes @engine.metrics, 'External/www.google.com/Net::HTTP/GET'
    assert_includes @engine.metrics, 'External/allOther'
    assert_includes @engine.metrics, 'External/www.google.com/all'

    assert_not_includes @engine.metrics, 'External/allWeb'
  end

  def test_ignore
    NewRelic::Agent.disable_all_tracing do
      url = URI.parse('http://www.google.com/index.html')
      res = Net::HTTP.start(url.host, url.port) {|http|
        http.post('/index.html','data')
      }
    end

    assert_not_includes @engine.metrics, 'External/all'
    assert_not_includes @engine.metrics, 'External/www.google.com/Net::HTTP/GET'
    assert_not_includes @engine.metrics, 'External/allOther'
    assert_not_includes @engine.metrics, 'External/www.google.com/all'

    assert_not_includes @engine.metrics, 'External/allWeb'
  end
    
  def test_head
    url = URI.parse('http://www.google.com/index.html')
    res = Net::HTTP.start(url.host, url.port) {|http|
      http.head('/index.html')
    }

    assert_includes @engine.metrics, 'External/all'
    assert_includes @engine.metrics, 'External/www.google.com/Net::HTTP/HEAD'
    assert_includes @engine.metrics, 'External/allOther'
    assert_includes @engine.metrics, 'External/www.google.com/all'

    assert_not_includes @engine.metrics, 'External/allWeb'
  end

  def test_post
    url = URI.parse('http://www.google.com/index.html')
    res = Net::HTTP.start(url.host, url.port) {|http|
      http.post('/index.html','data')
    }

    assert_includes @engine.metrics, 'External/all'
    assert_includes @engine.metrics, 'External/www.google.com/Net::HTTP/POST'
    assert_includes @engine.metrics, 'External/allOther'
    assert_includes @engine.metrics, 'External/www.google.com/all'

    assert_not_includes @engine.metrics, 'External/allWeb'
  end

  # When an http call is made, the agent should add a request header named
  # X-NewRelic-ID with a value equal to the encoded cross_app_id.

  def test_adds_a_request_header_to_outgoing_requests_if_xp_enabled
    @socket.check_write do |data|

      # assert_match /(?i:x-newrelic-id): VURQV1BZRkZdXUFT/, data
      # The above assertion won't work in Ruby 2.0.0-p0 because of a bug in the
      # regexp engine.  Until that's fixed we'll check the header name case
      # sensitively.
      assert_match /X-Newrelic-Id: VURQV1BZRkZdXUFT/, data
    end

    with_config(:"cross_application_tracer.enabled" => true) do
      Net::HTTP.get URI.parse('http://www.google.com/index.html')
    end
  end

  def test_adds_a_request_header_to_outgoing_requests_if_old_xp_config_is_present
    @socket.check_write do |data|
      # assert_match /(?i:x-newrelic-id): VURQV1BZRkZdXUFT/, data
      # The above assertion won't work in Ruby 2.0.0-p0 because of a bug in the
      # regexp engine.  Until that's fixed we'll check the header name case
      # sensitively.
      assert_match /X-Newrelic-Id: VURQV1BZRkZdXUFT/, data
    end

    with_config(:cross_application_tracing => true) do
      Net::HTTP.get URI.parse('http://www.google.com/index.html')
    end
  end

  def test_agent_doesnt_add_a_request_header_to_outgoing_requests_if_xp_disabled
    @socket.check_write do |data|
      # assert_no_match /(?i:x-newrelic-id): VURQV1BZRkZdXUFT/, data
      # The above assertion won't work in Ruby 2.0.0-p0 because of a bug in the
      # regexp engine.  Until that's fixed we'll check the header name case
      # sensitively.
      assert_no_match /X-Newrelic-Id: VURQV1BZRkZdXUFT/, data
    end

    Net::HTTP.get URI.parse('http://www.google.com/index.html')
  end


  def test_instrumentation_with_crossapp_enabled_records_normal_metrics_if_no_header_present
    with_config(:"cross_application_tracer.enabled" => true) do
      Net::HTTP.get URI.parse('http://www.google.com/index.html')
    end

    assert_equal 5, @engine.metrics.length

    assert_includes @engine.metrics, 'External/all'
    assert_includes @engine.metrics, 'External/allOther'
    assert_includes @engine.metrics, 'External/www.google.com/Net::HTTP/GET'
    assert_includes @engine.metrics, 'External/www.google.com/all'
    assert_includes @engine.metrics, 'External/www.google.com/Net::HTTP/GET:test'

    assert_not_includes @engine.metrics, 'ExternalApp/www.google.com/18#1884/all'
    assert_not_includes @engine.metrics, 'ExternalTransaction/www.google.com/18#1884/txn-name'
    assert_not_includes @engine.metrics, 'External/allWeb'
  end


  def test_instrumentation_with_crossapp_disabled_records_normal_metrics_even_if_header_is_present
    @response[ NR_APPDATA_HEADER ] = 
      make_app_data_payload( '18#1884', 'txn-name', 2, 8, 0, TRANSACTION_GUID )

    Net::HTTP.get URI.parse('http://www.google.com/index.html')

    assert_equal 5, @engine.metrics.length

    assert_includes @engine.metrics, 'External/all'
    assert_includes @engine.metrics, 'External/allOther'
    assert_includes @engine.metrics, 'External/www.google.com/Net::HTTP/GET'
    assert_includes @engine.metrics, 'External/www.google.com/all'
    assert_includes @engine.metrics, 'External/www.google.com/Net::HTTP/GET:test'

    assert_not_includes @engine.metrics, 'ExternalApp/www.google.com/18#1884/all'
    assert_not_includes @engine.metrics, 'ExternalTransaction/www.google.com/18#1884/txn-name'
    assert_not_includes @engine.metrics, 'External/allWeb'
  end


  def test_instrumentation_with_crossapp_enabled_records_crossapp_metrics_if_header_present
    @response[ NR_APPDATA_HEADER ] = 
      make_app_data_payload( '18#1884', 'txn-name', 2, 8, 0, TRANSACTION_GUID )

    with_config(:"cross_application_tracer.enabled" => true) do
      Net::HTTP.get URI.parse('http://www.google.com/index.html')
    end

    assert_equal 6, @engine.metrics.length

    assert_includes @engine.metrics, 'External/all'
    assert_includes @engine.metrics, 'External/allOther'
    assert_includes @engine.metrics, 'ExternalApp/www.google.com/18#1884/all'
    assert_includes @engine.metrics, 'ExternalTransaction/www.google.com/18#1884/txn-name'
    assert_includes @engine.metrics, 'External/www.google.com/all'
    assert_includes @engine.metrics, 'ExternalTransaction/www.google.com/18#1884/txn-name:test'

    assert_not_includes @engine.metrics, 'External/www.google.com/Net::HTTP/GET'
    assert_not_includes @engine.metrics, 'External/allWeb'

    last_segment = find_last_segment()

    assert_includes last_segment.params.keys, :transaction_guid
    assert_equal TRANSACTION_GUID, last_segment.params[:transaction_guid]
  end

  def test_crossapp_metrics_allow_valid_utf8_characters
    @response[ NR_APPDATA_HEADER ] = 
      make_app_data_payload( '12#1114', '世界線航跡蔵', 18.0, 88.1, 4096, TRANSACTION_GUID )

    with_config(:"cross_application_tracer.enabled" => true) do
      Net::HTTP.get URI.parse('http://www.google.com/index.html')
    end

    assert_equal 6, @engine.metrics.length

    assert_includes @engine.metrics, 'External/all'
    assert_includes @engine.metrics, 'External/allOther'
    assert_includes @engine.metrics, 'ExternalApp/www.google.com/12#1114/all'
    assert_includes @engine.metrics, 'ExternalTransaction/www.google.com/12#1114/世界線航跡蔵'
    assert_includes @engine.metrics, 'External/www.google.com/all'
    assert_includes @engine.metrics, 'ExternalTransaction/www.google.com/12#1114/世界線航跡蔵:test'

    assert_not_includes @engine.metrics, 'External/www.google.com/Net::HTTP/GET'
    assert_not_includes @engine.metrics, 'External/allWeb'

    last_segment = find_last_segment()

    assert_includes last_segment.params.keys, :transaction_guid
    assert_equal TRANSACTION_GUID, last_segment.params[:transaction_guid]
  end

  def test_crossapp_metrics_ignores_crossapp_header_with_malformed_crossprocess_id
    @response[ NR_APPDATA_HEADER ] = 
      make_app_data_payload( '88#88#88', 'invalid', 1, 2, 4096, TRANSACTION_GUID )

    with_config(:"cross_application_tracer.enabled" => true) do
      Net::HTTP.get URI.parse('http://www.google.com/index.html')
    end

    assert_equal 5, @engine.metrics.length

    assert_includes @engine.metrics, 'External/all'
    assert_includes @engine.metrics, 'External/allOther'
    assert_includes @engine.metrics, 'External/www.google.com/Net::HTTP/GET'
    assert_includes @engine.metrics, 'External/www.google.com/all'
    assert_includes @engine.metrics, 'External/www.google.com/Net::HTTP/GET:test'

    assert_not_includes @engine.metrics, 'ExternalApp/www.google.com/88#88#88/all'
    assert_not_includes @engine.metrics, 'ExternalTransaction/www.google.com/88#88#88/invalid'
    assert_not_includes @engine.metrics, 'External/allWeb'
  end

  def test_doesnt_affect_the_request_if_an_exception_is_raised_while_setting_up_tracing
    res = nil
    NewRelic::Agent.instance.stats_engine.stubs( :push_scope ).
      raises( NoMethodError, "undefined method `push_scope'" )

    with_config(:"cross_application_tracer.enabled" => true) do
      assert_nothing_raised do
        res = Net::HTTP.get URI.parse('http://www.google.com/index.html')
      end
    end

    assert_equal res, CANNED_RESPONSE.instance_variable_get( :@body )
  end

  def test_doesnt_affect_the_request_if_an_exception_is_raised_while_finishing_tracing
    res = nil
    NewRelic::Agent.instance.stats_engine.stubs( :pop_scope ).
      raises( NoMethodError, "undefined method `pop_scope'" )

    with_config(:"cross_application_tracer.enabled" => true) do
      assert_nothing_raised do
        res = Net::HTTP.get URI.parse('http://www.google.com/index.html')
      end
    end

    assert_equal res, CANNED_RESPONSE.instance_variable_get( :@body )
  end

  def test_scope_stack_integrity_maintained_on_request_failure
    @socket.stubs(:write).raises('fake network error')
    with_config(:"cross_application_tracer.enabled" => true) do
      assert_nothing_raised do
        expected = @engine.push_scope('dummy')
        Net::HTTP.get(URI.parse('http://www.google.com/index.html')) rescue nil
        @engine.pop_scope(expected, 42)
      end
    end
  end

  def test_doesnt_misbehave_when_transaction_tracing_is_disabled
    @engine.transaction_sampler = nil

    # The error should have any other consequence other than logging the error, so
    # this will capture logs
    logger = NewRelic::Agent::MemoryLogger.new
    NewRelic::Agent.logger = logger

    with_config(:"cross_application_tracer.enabled" => true) do
      Net::HTTP.get(URI.parse('http://www.google.com/index.html'))
    end

    assert_no_match( /undefined method `rename_scope_segment' for nil:NilClass/i,
                     logger.messages.flatten.map {|log| log.to_s }.join(' ') )

  ensure
    @engine.transaction_sampler = NewRelic::Agent.agent.transaction_sampler
  end

end
