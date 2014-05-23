# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class FakeThread
  @@list = []

  def initialize(locals={}, &block)
    @locals = locals
    yield if block_given?
  end

  def self.current
    {}
  end

  def self.list
    @@list
  end

  def alive?
    true
  end

  def key?(key)
    @locals.key?(key)
  end

  def [](key)
    @locals[key]
  end

  def []=(key, value)
    @locals[key] = value
  end

  def backtrace
    @locals[:backtrace] || []
  end

  def join
  end
end
