require File.expand_path(File.join(File.dirname(__FILE__),'/../../../../../../test/test_helper'))
require 'newrelic/agent/collection_helper'
require 'ostruct'

class NewRelic::Agent::CollectionHelperTests < Test::Unit::TestCase
  include CollectionHelper
  def test_string
    val = ('A'..'Z').to_a.join * 100
    assert_equal val.first(256) + "...", normalize_params(val)
  end
  def test_boolean
    np = normalize_params(APP_CONFIG)
    assert_equal false, np['disable_ui']
  end
  def test_number
    np = normalize_params({ 'one' => 1.0, 'two' => '2'})
  end
  def test_nil
    np = normalize_params({ nil => 1.0, 'two' => 'nil'})
    assert_equal "1.0", np[nil]
    assert_equal nil, np['two']
  end
  def test_hash
    val = ('A'..'Z').to_a.join * 100
    assert_equal Hash["ABCDEFGHIJKLMNOPQRSTUVWXYZABCDEF..." => (("0"*256) + "...")], normalize_params({ val => '0' * 512 })
  end
  
  def test_object
    assert_equal ["foo", '#<OpenStruct z="q">'], normalize_params(['foo', OpenStruct.new('z'=>'q')])
  end
  
end
