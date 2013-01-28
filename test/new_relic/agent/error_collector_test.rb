# Run faster standalone
ENV['SKIP_RAILS'] = 'true'
require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))

class NewRelic::Agent::ErrorCollectorTest < Test::Unit::TestCase
  def setup
    super
    @test_config = { :capture_params => true }
    NewRelic::Agent.config.apply_config(@test_config)
    @error_collector = NewRelic::Agent::ErrorCollector.new
    @error_collector.stubs(:enabled).returns(true)
  end

  def teardown
    super
    NewRelic::Agent.config.remove_config(@test_config)
  end

  def test_empty
    @error_collector.harvest_errors([])
    @error_collector.notice_error(nil, :metric=> 'path', :request_params => {:x => 'y'})
    errors = @error_collector.harvest_errors([])

    assert_equal 0, errors.length

    @error_collector.notice_error('Some error message', :metric=> 'path', :request_params => {:x => 'y'})
    errors = @error_collector.harvest_errors([])

    err = errors.first
    assert_equal 'Some error message', err.message
    assert_equal 'y', err.params[:request_params][:x]
    assert_equal '', err.params[:request_uri]
    assert_equal '', err.params[:request_referer]
    assert_equal 'path', err.path
    assert_equal 'Error', err.exception_class
  end

  def test_simple
    @error_collector.notice_error(StandardError.new("message"), :uri => '/myurl/', :metric => 'path', :referer => 'test_referer', :request_params => {:x => 'y'})

    old_errors = []
    errors = @error_collector.harvest_errors(old_errors)

    assert_equal errors.length, 1

    err = errors.first
    assert_equal 'message', err.message
    assert_equal 'y', err.params[:request_params][:x]
    assert err.params[:request_uri] == '/myurl/'
    assert err.params[:request_referer] == "test_referer"
    assert err.path == 'path'
    assert err.exception_class == 'StandardError'

    # the collector should now return an empty array since nothing
    # has been added since its last harvest
    errors = @error_collector.harvest_errors(nil)
    assert errors.length == 0
  end

  def test_long_message
    #yes, times 500. it's a 5000 byte string. Assuming strings are
    #still 1 byte / char.
    @error_collector.notice_error(StandardError.new("1234567890" * 500), :uri => '/myurl/', :metric => 'path', :request_params => {:x => 'y'})

    old_errors = []
    errors = @error_collector.harvest_errors(old_errors)

    assert_equal errors.length, 1

    err = errors.first
    assert_equal 4096, err.message.length
    assert_equal ('1234567890' * 500)[0..4095], err.message
  end

  def test_collect_failover
    @error_collector.notice_error(StandardError.new("message"), :metric => 'first', :request_params => {:x => 'y'})

    errors = @error_collector.harvest_errors([])

    @error_collector.notice_error(StandardError.new("message"), :metric => 'second', :request_params => {:x => 'y'})
    @error_collector.notice_error(StandardError.new("message"), :metric => 'path', :request_params => {:x => 'y'})
    @error_collector.notice_error(StandardError.new("message"), :metric => 'last', :request_params => {:x => 'y'})

    errors = @error_collector.harvest_errors(errors)

    assert_equal 4, errors.length
    assert_equal 'first', errors.first.path
    assert_equal 'last', errors.last.path

    @error_collector.notice_error(StandardError.new("message"), :metric => 'first', :request_params => {:x => 'y'})
    @error_collector.notice_error(StandardError.new("message"), :metric => 'last', :request_params => {:x => 'y'})

    errors = @error_collector.harvest_errors(nil)
    assert_equal 2, errors.length
    assert_equal 'first', errors.first.path
    assert_equal 'last', errors.last.path
  end

  def test_queue_overflow

    max_q_length = 20     # for some reason I can't read the constant in ErrorCollector

    silence_stream(::STDOUT) do
     (max_q_length + 5).times do |n|
        @error_collector.notice_error(StandardError.new("exception #{n}"), :metric => "path", :request_params => {:x => n})
      end
    end

    errors = @error_collector.harvest_errors([])
    assert errors.length == max_q_length
    errors.each_index do |i|
      err = errors.shift
      assert_equal i.to_s, err.params[:request_params][:x], err.params.inspect
    end
  end

  # Why would anyone undef these methods?
  class TestClass
    undef to_s
    undef inspect
  end


  def test_supported_param_types
    types = [[1, '1'],
    [1.1, '1.1'],
    ['hi', 'hi'],
    [:hi, :hi],
    [StandardError.new("test"), "#<StandardError>"],
    [TestClass.new, "#<NewRelic::Agent::ErrorCollectorTest::TestClass>"]
    ]

    types.each do |test|
      @error_collector.notice_error(StandardError.new("message"), :metric => 'path',
                                    :request_params => {:x => test[0]})
      assert_equal test[1], @error_collector.harvest_errors([])[0].params[:request_params][:x]
    end
  end


  def test_exclude
    @error_collector.ignore(["IOError"])

    @error_collector.notice_error(IOError.new("message"), :metric => 'path', :request_params => {:x => 'y'})

    errors = @error_collector.harvest_errors([])

    assert_equal 0, errors.length
  end

  def test_exclude_later_config_changes
    @error_collector.notice_error(IOError.new("message"))

    NewRelic::Agent.config.apply_config(:'error_collector.ignore_errors' => "IOError")
    @error_collector.notice_error(IOError.new("message"))

    errors = @error_collector.harvest_errors([])

    assert_equal 1, errors.length

  end

  def test_exclude_block
    @error_collector.ignore_error_filter &wrapped_filter_proc
        
    @error_collector.notice_error(IOError.new("message"), :metric => 'path', :request_params => {:x => 'y'})
    @error_collector.notice_error(StandardError.new("message"), :metric => 'path', :request_params => {:x => 'y'})
    
    errors = @error_collector.harvest_errors([])

    assert_equal 1, errors.length
  end

  def test_obfuscates_error_messages_when_high_security_is_set
    with_config(:high_security => true) do
      @error_collector.notice_error(StandardError.new("YO SQL BAD: serect * flom test where foo = 'bar'"))
      @error_collector.notice_error(StandardError.new("YO SQL BAD: serect * flom test where foo in (1,2,3,4,5)"))

      old_errors = []
      errors = @error_collector.harvest_errors([])

      assert_equal('YO SQL BAD: serect * flom test where foo = ?',
                   errors[0].message)
      assert_equal('YO SQL BAD: serect * flom test where foo in (?,?,?,?,?)',
                   errors[1].message)
    end
  end

  private
  
  def wrapped_filter_proc
    Proc.new do |e|
      if e.is_a? IOError
        return nil
      else
        return e
      end
    end
  end
  
  def silence_stream(*args)
    super
  rescue NoMethodError
    yield
  end
end
