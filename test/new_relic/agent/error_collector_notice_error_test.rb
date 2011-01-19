require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper')) 
class NewRelic::Agent::ErrorCollectorNoticeErrorTest < Test::Unit::TestCase
  require 'new_relic/agent/error_collector'
  include NewRelic::Agent::ErrorCollector::NoticeError
  
  def test_uri_ref_and_root_default
    fake_control = mocked_control
    fake_control.expects(:root).returns('rootbeer')
    options = {}
    assert_equal({:request_referer => '', :rails_root => 'rootbeer', :request_uri => ''}, uri_ref_and_root(options))
  end

  def test_uri_ref_and_root_values
    fake_control = mocked_control
    fake_control.expects(:root).returns('rootbeer')    
    options = {:uri => 'whee', :referer => 'bang'}
    assert_equal({:request_referer => 'bang', :rails_root => 'rootbeer', :request_uri => 'whee'}, uri_ref_and_root(options))    
  end

  def test_custom_params_from_opts_base
    assert_equal({}, custom_params_from_opts({}))
  end

  def test_custom_params_from_opts_custom_params
    assert_equal({:foo => 'bar'}, custom_params_from_opts({:custom_params => {:foo => 'bar'}}))
  end

  def test_custom_params_from_opts_merged_params
    assert_equal({:foo => 'baz'}, custom_params_from_opts({:custom_params => {:foo => 'bar'}, :foo => 'baz'}))
  end

  def test_request_params_from_opts_positive
    fake_control = mock('control')
    self.expects(:control).returns(fake_control)
    fake_control.expects(:capture_params).returns(true)
    val = {:request_params => 'foo'}
    assert_equal('foo', request_params_from_opts(val))
    assert_equal({}, val, "should delete request_params key from hash")
  end

  def test_request_params_from_opts_negative
    fake_control = mock('control')
    self.expects(:control).returns(fake_control)
    fake_control.expects(:capture_params).returns(false)
    val = {:request_params => 'foo'}
    assert_equal(nil, request_params_from_opts(val))
    assert_equal({}, val, "should delete request_params key from hash")
  end
  
  def test_normalized_request_and_custom_params_base
    self.expects(:normalize_params).with(nil).returns(nil)
    self.expects(:normalize_params).with({}).returns({})
    fake_control = mock('control')
    self.expects(:control).returns(fake_control)
    fake_control.expects(:capture_params).returns(true)
    assert_equal({:request_params => nil, :custom_params => {}}, normalized_request_and_custom_params({}))
  end

  def test_error_params_default
    self.expects(:normalize_params).with(nil).returns(nil)
    self.expects(:normalize_params).with({}).returns({})
    fake_control = mocked_control
    fake_control.expects(:root).returns('rootbeer')
    fake_control.expects(:capture_params).returns(true)
    options = {}
    assert_equal({:request_referer => '', :rails_root => 'rootbeer', :request_uri => '', :custom_params => {}, :request_params => nil}, error_params_from_options(options))
  end

  def test_error_params_uri_and_ref
    self.expects(:normalize_params).with(nil).returns(nil)
    self.expects(:normalize_params).with({}).returns({})
    fake_control = mocked_control
    fake_control.expects(:root).returns('rootbeer')
    fake_control.expects(:capture_params).returns(true)
    options = {:uri => 'whee', :referer => 'bang'}
    assert_equal({:request_referer => 'bang', :rails_root => 'rootbeer', :request_uri => 'whee', :custom_params => {}, :request_params => nil}, error_params_from_options(options))
  end
  
  def test_should_exit_notice_error_disabled
    error = mocked_error
    @enabled = false
    assert should_exit_notice_error?(error)
  end

  def test_should_exit_notice_error_nil
    error = nil
    @enabled = true
    self.expects(:error_is_ignored?).with(error).returns(false)
    # we increment it for the case that someone calls
    # NewRelic::Agent.notice_error(foo) # foo is nil
    # (which is probably not a good idea but is the existing api)
    self.expects(:increment_error_count!)
    assert should_exit_notice_error?(error)
  end

  def test_should_exit_notice_error_positive
    error = mocked_error
    @enabled = true
    self.expects(:error_is_ignored?).with(error).returns(true)
    assert should_exit_notice_error?(error)
  end

  def test_should_exit_notice_error_negative
    error = mocked_error
    @enabled = true
    self.expects(:error_is_ignored?).with(error).returns(false)
    self.expects(:increment_error_count!)
    assert !should_exit_notice_error?(error)
  end

  def test_filtered_error_positive
    @ignore = {'an_error' => true}
    error = mocked_error
    error_class = mock('error class')
    error.expects(:class).returns(error_class)
    error_class.expects(:name).returns('an_error')
    assert filtered_error?(error)
  end

  def test_filtered_error_negative
    @ignore = {}
    error = mocked_error
    error_class = mock('error class')
    error.expects(:class).returns(error_class)
    error_class.expects(:name).returns('an_error')
    self.expects(:filtered_by_error_filter?).with(error).returns(false)
    assert !filtered_error?(error)
  end

  def test_filtered_by_error_filter_empty
    # should return right away when there's no filter
    @ignore_filter = nil
    assert !filtered_by_error_filter?(nil)
  end

  def test_filtered_by_error_filter_positive
    error = mocked_error
    @ignore_filter = lambda { |x| assert_equal error, x; false  }
    assert filtered_by_error_filter?(error)
  end

  def test_filtered_by_error_filter_negative
    error = mocked_error
    @ignore_filter = lambda { |x| assert_equal error, x; true  }
    assert !filtered_by_error_filter?(error)
  end

  def test_error_is_ignored_positive
    error = mocked_error
    self.expects(:filtered_error?).with(error).returns(true)
    assert error_is_ignored?(error)
  end

  def test_error_is_ignored_negative
    error = mocked_error
    self.expects(:filtered_error?).with(error).returns(false)
    assert !error_is_ignored?(error)
  end

  def test_error_is_ignored_no_error
    assert !error_is_ignored?(nil), 'should not ignore nil'
  end

  private

  def mocked_error
    mock('error')
  end

  def mocked_control
    fake_control = mock('control')
    self.stubs(:control).returns(fake_control)
    fake_control
  end
end
