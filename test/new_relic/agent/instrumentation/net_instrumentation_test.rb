#-*- ruby -*-

require 'net/http'

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

    def metrics_without_gc
      @engine.metrics - ['GC/cumulative']
    end

    private :metrics_without_gc

    def test_get
      url = URI.parse('http://www.google.com/index.html')
      res = Net::HTTP.start(url.host, url.port) {|http|
        http.get('/index.html')
      }
      assert_match /<head>/i, res.body
      assert_equal %w[External/all External/www.google.com/Net::HTTP/GET External/allOther External/www.google.com/all].sort,
        metrics_without_gc.sort
    end

    def test_background
      perform_action_with_newrelic_trace("task", :category => :task) do
        url = URI.parse('http://www.google.com/index.html')
        res = Net::HTTP.start(url.host, url.port) {|http|
          http.get('/index.html')
        }
        assert_match /<head>/i, res.body
      end
      assert_equal %w[External/all External/www.google.com/Net::HTTP/GET External/allOther External/www.google.com/all
       External/www.google.com/Net::HTTP/GET:OtherTransaction/Background/NewRelic::Agent::Instrumentation::NetInstrumentationTest/task].sort, metrics_without_gc.select{|m| m =~ /^External/}.sort
    end

    def test_transactional
      perform_action_with_newrelic_trace("task") do
        url = URI.parse('http://www.google.com/index.html')
        res = Net::HTTP.start(url.host, url.port) {|http|
          http.get('/index.html')
        }
        assert_match /<head>/i, res.body
      end
      assert_equal %w[External/all External/www.google.com/Net::HTTP/GET External/allWeb External/www.google.com/all
       External/www.google.com/Net::HTTP/GET:Controller/NewRelic::Agent::Instrumentation::NetInstrumentationTest/task].sort, metrics_without_gc.select{|m| m =~ /^External/}.sort
    end
    def test_get__simple
      Net::HTTP.get URI.parse('http://www.google.com/index.html')
      assert_equal metrics_without_gc.sort,
      %w[External/all External/www.google.com/Net::HTTP/GET External/allOther External/www.google.com/all].sort
    end
    def test_ignore
      NewRelic::Agent.disable_all_tracing do
        url = URI.parse('http://www.google.com/index.html')
        res = Net::HTTP.start(url.host, url.port) {|http|
          http.post('/index.html','data')
        }
      end
      assert_equal 0, metrics_without_gc.size
    end
    def test_head
      url = URI.parse('http://www.google.com/index.html')
      res = Net::HTTP.start(url.host, url.port) {|http|
        http.head('/index.html')
      }
      assert_equal %w[External/all External/www.google.com/Net::HTTP/HEAD External/allOther External/www.google.com/all].sort,
      metrics_without_gc.sort
    end

    def test_post
      url = URI.parse('http://www.google.com/index.html')
      res = Net::HTTP.start(url.host, url.port) {|http|
        http.post('/index.html','data')
      }
      assert_equal %w[External/all External/www.google.com/Net::HTTP/POST External/allOther External/www.google.com/all].sort,
      metrics_without_gc.sort
    end

  end
end
