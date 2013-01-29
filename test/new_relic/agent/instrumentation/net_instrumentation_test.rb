#-*- ruby -*-

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
      NewRelic::Agent.manual_start
      @engine = NewRelic::Agent.instance.stats_engine
      @engine.clear_stats

      # Don't actually talk to Google.
      @socket = stub("socket") do
        stubs(:closed?).returns(false)
        stubs(:close)
        stubs(:read_nonblock).returns(CANNED_RESPONSE).then.raises(EOFError)

        def self.write( buf )
          buf.length
        end
      end
      TCPSocket.stubs(:open).returns(@socket)
    end

    
    #
    # Helpers
    #

    def metrics_without_gc
      @engine.metrics - ['GC/cumulative']
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
        'External/www.google.com/Net::HTTP/GET:OtherTransaction/Background/' +
        'NewRelic::Agent::Instrumentation::NetInstrumentationTest/task'
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
        'External/www.google.com/Net::HTTP/GET:Controller/' +
        'NewRelic::Agent::Instrumentation::NetInstrumentationTest/task'
    end
    
    def test_get__simple
      Net::HTTP.get URI.parse('http://www.google.com/index.html')

      assert_includes @engine.metrics, 'External/all'
      assert_includes @engine.metrics, 'External/www.google.com/Net::HTTP/GET'
      assert_includes @engine.metrics, 'External/allOther'
      assert_includes @engine.metrics, 'External/www.google.com/all'
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
    end

  end
end
