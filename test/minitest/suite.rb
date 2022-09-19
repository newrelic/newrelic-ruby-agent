# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class Suite
  attr_reader :name
  def initialize(name)
    @name = name
  end

  def ==(other)
    name == other.name
  end

  def eql?(other)
    self == other
  end

  def hash
    name.hash
  end

  def to_s
    name.to_s
  end
end
