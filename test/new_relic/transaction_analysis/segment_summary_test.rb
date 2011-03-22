require File.expand_path(File.join(File.dirname(__FILE__),'..', '..','test_helper')) 
require 'new_relic/transaction_analysis/segment_summary'
class NewRelic::TransactionAnalysis::SegmentSummaryTest < Test::Unit::TestCase
  
  def setup
    @ss = SegmentSummary.new
  end
  
  # these are mostly stub tests just making sure that the API doesn't
  # change if anyone ever needs to modify it.
  
  def test_fail
    raise 'needs more tests'
  end
end
