# this struct uniquely defines a metric, optionally inside
# the call scope of another metric
class NewRelic::MetricSpec
  attr_accessor   :name
  attr_accessor   :scope
  
  def initialize (name, scope = nil)
    self.name = name
    self.scope = scope
  end
  
  def eql? (o)
    if scope.nil? 
      return name.eql?(o.name)
    end
    name.eql?(o.name) && scope.eql?(o.scope)
  end
  
  def hash
    h = name.hash
    h += scope.hash unless scope.nil?
    h
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
