# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/transaction_sample'
require 'new_relic/transaction_sample/segment'
module NewRelic
  class TransactionSample
    class FakeSegment < Segment
      public :parent_segment=
    end
  end
end
