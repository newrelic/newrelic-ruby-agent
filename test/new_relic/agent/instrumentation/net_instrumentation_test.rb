#!/usr/bin/env ruby
# encoding: utf-8

require 'net/http'
require 'pp'

unless ENV['FAST_TESTS']
  require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

  class NewRelic::Agent::Instrumentation::NetInstrumentationTest < Test::Unit::TestCase
    include NewRelic::Agent::Instrumentation::ControllerInstrumentation

    CANNED_RESPONSE = (<<-"END_RESPONSE").gsub(/^    /m, '')
    HTTP/1.1 200 OK
    status: 200 OK
    version: HTTP/1.1
    cache-control: private, max-age=0
    content-type: text/html; charset=UTF-8
    date: Tue, 29 Jan 2013 21:52:04 GMT
    expires: -1
    server: gws
    x-frame-options: SAMEORIGIN
    x-xss-protection: 1; mode=block
    
    <html><head><title>Canned Response</title></head><body>Canned response.</body></html>
    END_RESPONSE


    def setup
      NewRelic::Agent.manual_start( :'cross_process.enabled' => false )
      @engine = NewRelic::Agent.instance.stats_engine
      @engine.clear_stats

      # Don't actually talk to Google.
      @socket = stub("socket") do
        stubs(:closed?).returns(false)
        stubs(:close)

        def self.write( buf )
          buf.length
        end
      end

      # Have to do this one outside of the block so the ivar is in the right context
      @response_data = CANNED_RESPONSE.dup
      if IO.const_defined?( :WaitReadable ) # Non-blocking IO in Net::Protocol?
        @socket.stubs(:read_nonblock).returns(@response_data).then.raises(EOFError)
      else
        @socket.stubs(:sysread).returns(@response_data).then.raises(EOFError)
      end

      TCPSocket.stubs(:open).returns(@socket)
    end

    #
    # Helpers
    #

    def metrics_without_gc
      @engine.metrics - ['GC/cumulative']
    end


    def make_app_data_payload( *args )
      return [ args.to_json ].pack( 'm' ).
        gsub( /\n/, '' ).
        gsub( /(.{59})(?=.)/, "\\1\r\n  " ) + "\n"
    end

    def make_app_data_header( *args )
      return "%s: %s" % [ Net::HTTP::NR_APPDATA_HEADER, make_app_data_payload(*args) ]
    end


    #
    # Tests
    #

    def test_get
      assert @response_data
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

    def test_instrumentation_fires_outgoing_service_call_hooks
      request = response = nil
      NewRelic::Agent.instance.events.subscribe(:before_http_request) do |arg|
        request = arg
      end
      NewRelic::Agent.instance.events.subscribe(:after_http_response) do |arg|
        response = arg
      end

      res = Net::HTTP.get( URI.parse('http://www.google.com/index.html') )

      assert_instance_of Net::HTTP::Get, request
      assert_equal 'GET', request.method
      assert_equal '/index.html', request.path

      assert_instance_of Net::HTTPOK, response
      assert_equal '200', response.code
      assert_match %r/<head>/i, response.body
    end


    def test_instrumentation_with_xprocess_enabled_records_normal_metrics_if_no_header_present
      with_config(:'cross_process.enabled' => true) do
        Net::HTTP.get URI.parse('http://www.google.com/index.html')
      end

      assert_includes @engine.metrics, 'External/all'
      assert_includes @engine.metrics, 'External/allOther'
      assert_includes @engine.metrics, 'External/www.google.com/Net::HTTP/GET'
      assert_includes @engine.metrics, 'External/www.google.com/all'

      assert_not_includes @engine.metrics, 'ExternalApp/www.google.com/18#1884/all'
      assert_not_includes @engine.metrics, 'ExternalTransaction/www.google.com/18#1884/txn-name'
      assert_not_includes @engine.metrics, 'External/allWeb'
    end


    def test_instrumentation_with_xprocess_enabled_records_xprocess_metrics_if_header_present
      app_data_header = make_app_data_header( '18#1884', 'txn-name', 2, 8, 0 )
      @response_data.sub!( /\n\n/, "\n" + app_data_header + "\n" )

      with_config(:'cross_process.enabled' => true) do
        Net::HTTP.get URI.parse('http://www.google.com/index.html')
      end

      assert_includes @engine.metrics, 'External/all'
      assert_includes @engine.metrics, 'External/allOther'
      assert_includes @engine.metrics, 'ExternalApp/www.google.com/18#1884/all'
      assert_includes @engine.metrics, 'ExternalTransaction/www.google.com/18#1884/txn-name'

      assert_not_includes @engine.metrics, 'External/www.google.com/Net::HTTP/GET'
      assert_not_includes @engine.metrics, 'External/www.google.com/all'
      assert_not_includes @engine.metrics, 'External/allWeb'
      
    end

    def test_xprocess_metrics_allow_valid_utf8_characters
      app_data_header = make_app_data_header( '12#1114', '世界線航跡蔵', 18.0, 88.1, 4096 )
      @response_data.sub!( /\n\n/, "\n" + app_data_header + "\n" )

      with_config(:'cross_process.enabled' => true) do
        Net::HTTP.get URI.parse('http://www.google.com/index.html')
      end

      assert_includes @engine.metrics, 'External/all'
      assert_includes @engine.metrics, 'External/allOther'
      assert_includes @engine.metrics, 'ExternalApp/www.google.com/12#1114/all'
      assert_includes @engine.metrics, 'ExternalTransaction/www.google.com/12#1114/世界線航跡蔵'

      assert_not_includes @engine.metrics, 'External/www.google.com/Net::HTTP/GET'
      assert_not_includes @engine.metrics, 'External/www.google.com/all'
      assert_not_includes @engine.metrics, 'External/allWeb'
      
    end

  end
end
