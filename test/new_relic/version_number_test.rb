require File.expand_path(File.join(File.dirname(__FILE__),'..', 'test_helper'))
class NewRelic::VersionNumberTest < Test::Unit::TestCase
  
  def test_comparison
    versions = %w[1.0.0 0.1.0 0.0.1 10.0.1 1.10.0].map {|s| NewRelic::VersionNumber.new s }
    assert_equal %w[0.0.1 0.1.0 1.0.0 1.10.0 10.0.1], versions.sort.map(&:to_s)
    v0 = NewRelic::VersionNumber.new '1.2.3'
    v1 = NewRelic::VersionNumber.new '1.2.2'
    v3 = NewRelic::VersionNumber.new '1.2.2'
    assert v0 > v1
    assert v1 == v1
    assert v1 == v3
  end
  def test_long_version
    v0 = NewRelic::VersionNumber.new '1.2.3.4'
    v1 = NewRelic::VersionNumber.new '1.2.3.3'
    v3 = NewRelic::VersionNumber.new '1.3'
    assert v0 > v1
    assert v3 > v0
  end
end