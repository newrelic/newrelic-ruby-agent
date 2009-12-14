# this struct uniquely defines a metric, optionally inside
# the call scope of another metric
class NewRelic::MetricSpec
  attr_accessor   :name
  attr_accessor   :scope
  
  def initialize (metric_name, metric_scope = '')
    self.name = metric_name
    self.scope = metric_scope
  end
  
  def eql? (o)
    scope_equal = scope.nil? ? o.scope.nil? : scope.eql?(o.scope) 
    name.eql?(o.name) && scope_equal
  end
  
  def hash
    h = name.hash
    h += scope.hash unless scope.nil?
    h
  end
  
  def to_s
    "#{name}:#{scope}"
  end
  
  def to_json(*a)
    {'name' => name, 
    'scope' => scope}.to_json(*a)
  end
  
  def <=>(o)
    namecmp = name <=> o.name
    return namecmp if namecmp != 0
    
    # i'm sure there's a more elegant way to code this correctly, but at least this passes
    # my unit test
    if scope.nil? && o.scope.nil?
      return 0
    elsif scope.nil?
      return -1
    elsif o.scope.nil?
      return 1
    else
      return scope <=> o.scope
    end
  end
end
