require File.expand_path(File.join(File.dirname(__FILE__),'..', 'test_helper'))
class NewRelic::VersionNumberTest < Test::Unit::TestCase
  
  def test_comparison
    versions = %w[1.0.0 0.1.0 0.0.1 10.0.1 1.10.0].map {|s| NewRelic::VersionNumber.new s }
    assert_equal %w[0.0.1 0.1.0 1.0.0 1.10.0 10.0.1], versions.sort.map(&:to_s)
  end
end