module NewRelic::Agent::CollectionHelper
  # Transform parameter hash into a hash whose values are strictly
  # strings
  def normalize_params(params)
    case params
      when Symbol, FalseClass, TrueClass, nil
        params
      when Numeric
        truncate(params.to_s)
      when String
        truncate(params)
      when Hash
        new_params = {}
        params.each do | key, value |
          new_params[truncate(normalize_params(key),32)] = normalize_params(value)
        end
        new_params
      when Array
        params.first(20).map{|item| normalize_params(item)}
    else
      truncate(flatten(params))
    end
  end
  
  # Return an array of strings (backtrace), cleaned up for readability
  # Return nil if there is no backtrace
  
  def strip_nr_from_backtrace(backtrace)
    if backtrace
      # strip newrelic from the trace
      backtrace = backtrace.reject {|line| line =~ /new_relic\/agent\// }
      # rename methods back to their original state
      backtrace = backtrace.collect {|line| line.gsub /_without_(newrelic|trace)/, ""}
    end
    backtrace
  end
  
  private
  
  # Convert any kind of object to a descriptive string
  # Only call this on unknown objects.  Otherwise call to_s.
  def flatten(object)
    s = 
      if object.respond_to? :inspect
        object.inspect
      elsif object.respond_to? :to_s
        object.to_s
      elsif object.nil?
        "nil"
      else
        "#<#{object.class.to_s}>"
      end

    if !(s.instance_of? String)
      s = "#<#{object.class.to_s}>"
    end
    
    s
  end
  
  def truncate(string, len=256)
    if string.instance_of? Symbol
      string
    elsif string.nil?
      ""
    elsif string.instance_of? String
      string.to_s.gsub(/^(.{#{len}})(.*)/) {$2.blank? ? $1 : $1 + "..."}
    else
      truncate(flatten(string), len)     
    end
  end
end
