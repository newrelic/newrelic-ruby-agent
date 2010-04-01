require File.expand_path(File.join(File.dirname(__FILE__),'..', '..', 'test_helper'))

class EpisodesTest < Test::Unit::TestCase
  
  def setup
    super
    @app = mock()
    @e = NewRelic::Rack::Episodes.new(@app)
    NewRelic::Agent.manual_start
    @agent = NewRelic::Agent.instance
    @agent.transaction_sampler.send :clear_builder
    @agent.transaction_sampler.reset!
    @agent.stats_engine.clear_stats
  end
  
  def test_match
    @e.expects(:process).times(3)
    @app.expects(:call).times(2)
    @e.call(mock_env('/newrelic/episodes/page_load/stuff'))    
    @e.call(mock_env('/newrelic/episodes/page_load'))
    @e.call(mock_env('/newrelic/episodes/page_load?'))
    
    @e.call(mock_env('/v2/newrelic/episodes/page_load?'))
    @e.call(mock_env('/v2'))
  end
  
  def test_process
    
    args = "ets=backend:2807,onload:7641,frontend:4835,pageready:7642,totaltime:7642&" +
           "url=/v2&"+
           "userAgent=Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10.6; en-US; rv:1.9.2.2) Gecko/20100316 Firefox/3.6.2"
    v = @e.call(mock_env("/newrelic/episodes/page_load?#{args}"))
    assert_equal 3, v.size
    assert_equal 204, v[0]
    compare_metrics %w[
      Client/totaltime
      Client/frontend
      Client/backend
      Client/onload
      Client/pageready
      ], @agent.stats_engine.metrics.grep(/^Client/)
    totaltime = @agent.stats_engine.get_stats_no_scope('Client/totaltime')
    assert_equal 1, totaltime.call_count
    assert_equal 7.642, totaltime.average_call_time

  end
  
  private
  
  def mock_env(uri_override)
    path, query = uri_override.split('?')
    
    Hash[
         'HTTP_ACCEPT'                  => 'application/xml,application/xhtml+xml,text/html;q=0.9,text/plain;q=0.8,image/png,*/*;q=0.5',
         'HTTP_ACCEPT_ENCODING'         => 'gzip, deflate',
         'HTTP_ACCEPT_LANGUAGE'         => 'en-us',
         'HTTP_CACHE_CONTROL'           => 'max-age=0',
         'HTTP_CONNECTION'              => 'keep-alive',
         'HTTP_COOKIE'                  => '_newrelic_development_session=BAh7CzoPc2Vzc2lvbl9pZCIlMTlkMGE5MTY1YmNhNTM5MjAxODRiNjdmNWY3ZTczOTU6D2FjY291bnRfaWRpBjoMdXNlcl9pZGkGOhNhcHBsaWNhdGlvbl9pZCIGMyIKZmxhc2hJQzonQWN0aW9uQ29udHJvbGxlcjo6Rmxhc2g6OkZsYXNoSGFzaHsABjoKQHVzZWR7ADoQdGltZV93aW5kb3dvOg9UaW1lV2luZG93CjoQQGJlZ2luX3RpbWVJdToJVGltZQ3OixuAAAAAGAY6H0BtYXJzaGFsX3dpdGhfdXRjX2NvZXJjaW9uRjoWQHJlcG9ydGluZ19wZXJpb2RpQToOQGVuZF90aW1lSXU7Dg3RixuAAAAAGAY7D0Y6DkBlbmRzX25vd1Q6D0ByYW5nZV9rZXk6EUxBU1RfM19IT1VSUw%3D%3D--ac863fb87fc0233caa5063398300a9b4c0c1fe71; _newrelic_local_production_session=BAh7CjoPc2Vzc2lvbl9pZCIlMjFmOGQzMmMwZmUxYjYzMjcyYjU1NzBkYmMyNzA5NTc6DHVzZXJfaWRpHjoTYXBwbGljYXRpb25faWQiCTE3NDY6D2FjY291bnRfaWRpPiIKZmxhc2hJQzonQWN0aW9uQ29udHJvbGxlcjo6Rmxhc2g6OkZsYXNoSGFzaHsABjoKQHVzZWR7AA%3D%3D--22ebf9e965e67d49430d8b9c2817302b37628766; auth_token=d0bf9b0468c3b994b23a0e1cdc712824ab4246d9',
         'HTTP_HOST'                    => 'localhost:3000',
         'HTTP_USER_AGENT'              => 'Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_6_2; en-us) AppleWebKit/531.22.7 (KHTML, like Gecko) Version/4.0.5 Safari/531.22.7',
         'HTTP_VERSION'                 => 'HTTP/1.1',
         'QUERY_STRING'                 => query,
         'REMOTE_ADDR'                  => '127.0.0.1',
         'REQUEST_METHOD'               => 'GET',
         'PATH_INFO'                    => path,
         'REQUEST_PATH'                 => path,
         'REQUEST_URI'                  => uri_override,
         'SCRIPT_NAME'                  => '',
         'SERVER_NAME'                  => 'localhost',
         'SERVER_PORT'                  => '3000',
         'SERVER_PROTOCOL'              => 'HTTP/1.1',
         'SERVER_SOFTWARE'              => 'Unicorn 0.97.0',
         'rack.input'                   => StringIO.new,
         'rack.errorst'                 => StringIO.new,
    #         'rack.logger'                  => '#<Logger:0x1014d7cc0>',
    #         'rack.session.options'         => 'path/key_session_idexpire_afterdomainhttponlytrue',
         'rack.multiprocess'            => 'true',
         'rack.multithread'             => 'false',
         'rack.run_once'                => 'false',
         'rack.session'                 => '',
         'rack.url_scheme'              => 'http',
         'rack.version'                 => '11'
    ]
  end
  
  def mock_routes
    ActionController::Routing::Routes.nil;
  end
end
