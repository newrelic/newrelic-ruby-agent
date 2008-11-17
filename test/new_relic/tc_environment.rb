require File.expand_path(File.join(File.dirname(__FILE__),'..', 'test_helper'))
require "test/unit"
require "mocha"
##require 'new_relic/local_environment'
class EnvironmentTest < ActiveSupport::TestCase
  
  def teardown
    # To remove mock server instances from ObjectSpace
    ObjectSpace.garbage_collect
    super
  end
  class MockOptions
    def fetch (*args)
      1000
    end
  end
  MOCK_OPTIONS = MockOptions.new
  
  def test_environment
    e = NewRelic::LocalEnvironment.new
    assert_equal :unknown, e.environment
    assert_nil e.identifier
  end
  def test_webrick
    Object.const_set :OPTIONS, { :port => 3000 }
    e = NewRelic::LocalEnvironment.new
    assert_equal :webrick, e.environment
    assert_equal 3000, e.identifier
    Object.class_eval { remove_const :OPTIONS }
  end
  def test_no_webrick
    Object.const_set :OPTIONS, 'foo'
    e = NewRelic::LocalEnvironment.new
    assert_equal :unknown, e.environment
    assert_nil e.identifier
    Object.class_eval { remove_const :OPTIONS }
  end
  def test_mongrel
    
    class << self
      module ::Mongrel
        class HttpServer
          def port; 3000; end
        end
      end
    end
    Mongrel::HttpServer.new
    e = NewRelic::LocalEnvironment.new
    assert_equal :mongrel, e.environment
    assert_equal 3000, e.identifier
    Mongrel::HttpServer.class_eval {undef_method :port}
  end
  def test_thin
    class << self
      module ::Thin
        class Server
          def backend; self; end
          def socket; "/socket/file.000"; end
        end
      end
    end
    mock_thin = Thin::Server.new
    e = NewRelic::LocalEnvironment.new
    assert_equal :thin, e.environment
    assert_equal '/socket/file.000', e.identifier
    mock_thin
  end
  def test_litespeed
    e = NewRelic::LocalEnvironment.new
    assert_equal :unknown, e.environment
    assert_nil e.identifier
  end
  def test_passenger
    class << self
      module ::Passenger
        const_set "AbstractServer", 0
      end
    end
    e = NewRelic::LocalEnvironment.new
    assert_equal :passenger, e.environment
    assert_equal 'passenger', e.identifier

    NewRelic::Config.instance.instance_eval do
      @settings['app_name'] = 'myapp'
    end
    
    e = NewRelic::LocalEnvironment.new 
    assert_equal :passenger, e.environment
    assert_equal 'passenger:myapp', e.identifier
    
    ::Passenger.class_eval { remove_const :AbstractServer }
  end

end