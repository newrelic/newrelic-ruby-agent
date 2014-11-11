# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# this struct uniquely defines a metric, optionally inside
# the call scope of another metric
class NewRelic::MetricSpec
  attr_reader   :name, :scope

  # the maximum length of a metric name or metric scope
  MAX_LENGTH = 255
  LENGTH_RANGE = (0...MAX_LENGTH)
  EMPTY_SCOPE = ''.freeze

  def initialize(metric_name='', metric_scope=nil)
    if metric_name.to_s.length > MAX_LENGTH
      @name = metric_name.to_s[LENGTH_RANGE]
    else
      @name = metric_name.to_s
    end

    if metric_scope
      if metric_scope.to_s.length > MAX_LENGTH
        @scope = metric_scope.to_s[LENGTH_RANGE]
      else
        @scope = metric_scope.to_s
      end
    else
      @scope = EMPTY_SCOPE
    end
  end

  def ==(o)
    self.eql?(o)
  end

  def eql? o
    @name == o.name && @scope == o.scope
  end

  def hash
    @name.hash ^ @scope.hash
  end

  # return a new metric spec if the given regex
  # matches the name or scope.
  def sub(pattern, replacement, apply_to_scope = true)
    ::NewRelic::Agent.logger.warn("The sub method on metric specs is deprecated") rescue nil
    return nil if name !~ pattern &&
     (!apply_to_scope || scope.nil? || scope !~ pattern)
    new_name = name.sub(pattern, replacement)[LENGTH_RANGE]

    if apply_to_scope
      new_scope = (scope && scope.sub(pattern, replacement)[LENGTH_RANGE])
    else
      new_scope = scope
    end

    self.class.new new_name, new_scope
  end

  def to_s
    return name if scope.empty?
    "#{name}:#{scope}"
  end

  def inspect
    "#<NewRelic::MetricSpec '#{name}':'#{scope}'>"
  end

  def to_json(*a)
    {'name' => name,
    'scope' => scope}.to_json(*a)
  end

  def <=>(o)
    namecmp = self.name <=> o.name
    return namecmp if namecmp != 0
    return (self.scope || '') <=> (o.scope || '')
  end
end
