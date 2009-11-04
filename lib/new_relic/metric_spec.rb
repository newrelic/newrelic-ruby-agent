# this struct uniquely defines a metric, optionally inside
# the call scope of another metric
class NewRelic::MetricSpec
  attr_accessor   :name
  attr_accessor   :scope
  
  def initialize (metric_name, metric_scope = '')
    self.name = metric_name
    self.scope = metric_scope
  end

  def ==(o)
    self.eql?(o)
  end
  
  def eql? o
    self.class == o.class &&
    name.eql?(o.name) && 
    # coerce scope to a string and compare
    (scope || '') == (o.scope || '')
  end
  
  def hash
    h = name.hash
    h ^= scope.hash unless scope.nil?
    h
  end
  # return a new metric spec if the given regex
  # matches the name or scope.
  def sub(pattern, replacement, apply_to_scope = true)
    return nil if name !~ pattern && 
                  (!apply_to_scope || scope.nil? || scope !~ pattern)
    new_name = name.sub(pattern, replacement)
    new_scope = (scope && scope.sub(pattern, replacement)) 
    self.class.new new_name, new_scope
  end
  
  def to_s
    "#{name}:#{scope}"
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
