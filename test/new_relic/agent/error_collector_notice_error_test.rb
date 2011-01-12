require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper')) 
class NewRelic::Agent::ErrorCollectorNoticeErrorTest < Test::Unit::TestCase
  require 'new_relic/agent/error_collector'
  include NewRelic::Agent::ErrorCollector::NoticeError
  
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
    @ignore_filter = lambda { |x| assert_equal error, x; true  }    
    assert filtered_by_error_filter?(error)
  end

  def test_filtered_by_error_filter_negative
    error = mocked_error
    @ignore_filter = lambda { |x| assert_equal error, x; false  }
    assert !filtered_by_error_filter?(error)
  end

  def test_error_is_ignored_positive
    assert false
  end

  def test_error_is_ignored_negative
    assert false
  end

  def test_error_is_ignored_no_error
    assert !error_is_ignored?(nil)
  end

  private

  def mocked_error
    mock('error')
  end
end
