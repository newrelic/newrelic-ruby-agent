# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

# this struct uniquely defines a metric, optionally inside
# the call scope of another metric
class NewRelic::MetricSpec
  attr_reader :name, :scope

  # the maximum length of a metric name or metric scope
  MAX_LENGTH = 255
  LENGTH_RANGE = (0...MAX_LENGTH)
  EMPTY_SCOPE = ''.freeze

  def initialize(metric_name = '', metric_scope = nil)
    @name = if metric_name.to_s.length > MAX_LENGTH
              metric_name.to_s[LENGTH_RANGE]
            else
              metric_name.to_s
            end

    @scope = if metric_scope
               if metric_scope.to_s.length > MAX_LENGTH
                 metric_scope.to_s[LENGTH_RANGE]
               else
                 metric_scope.to_s
               end
             else
               EMPTY_SCOPE
             end
  end

  def ==(other)
    eql?(other)
  end

  def eql?(other)
    @name == other.name && @scope == other.scope
  end

  def hash
    @name.hash ^ @scope.hash
  end

  def to_s
    return name if scope.empty?

    "#{name}:#{scope}"
  end

  def inspect
    "#<NewRelic::MetricSpec '#{name}':'#{scope}'>"
  end

  def to_json(*a)
    { 'name' => name,
      'scope' => scope }.to_json(*a)
  end

  def <=>(other)
    namecmp = name <=> other.name
    return namecmp if namecmp != 0

    (scope || '') <=> (other.scope || '')
  end
end
