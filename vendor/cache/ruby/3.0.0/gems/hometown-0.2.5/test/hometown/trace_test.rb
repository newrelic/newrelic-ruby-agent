require File.expand_path(File.join(File.dirname(__FILE__), "..", "test_helper"))
require 'hometown/trace'

module Hometown
  class TraceTest < Minitest::Test
    def test_equality
      trace1 = Trace.new(self.class, ["boo"])
      trace2 = Trace.new(self.class, ["boo"])

      assert trace1.eql?(trace2)
    end

    def test_inequality
      trace1 = Trace.new(self.class, ["boo"])
      trace2 = Trace.new(self.class, ["HOO"])

      refute trace1.eql?(trace2)
    end

    def test_hash
      trace1 = Trace.new(self.class, ["boo"])
      trace2 = Trace.new(self.class, ["boo"])

      assert_equal trace1.hash, trace2.hash
    end
  end
end
