# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class SizedBuffer
  attr_reader :dropped

  def initialize(capacity)
    @capacity = capacity
    reset!
  end

  def append(x)
    if @samples.size < @capacity
      @samples << x
      return true
    else
      @dropped += 1
      return false
    end
  end

  def to_a
    @samples.dup
  end

  def reset!
    @samples = []
    @dropped = 0
  end
end
