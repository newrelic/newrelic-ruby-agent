module CollectionHelper
  # Transform parameter hash into a hash whose values are strictly
  # strings
  def normalize_params(params)
    case params
      when Symbol, FalseClass, TrueClass, nil:
      params
      when Numeric
      params.to_s
      when String
      truncate(params, 256)
      when Hash:
      new_params = {}
      params.each do | key, value |
        new_params[truncate(normalize_params(key),32)] = normalize_params(value)
      end
      new_params
      when Enumerable:
      params.first(20).collect { | v | normalize_params(v)}
    else
      truncate(flatten(params), 256)
    end
  end
  
  
  def clean_exception(exception)
    exception = exception.original_exception if exception.respond_to? 'original_exception'
    
    if exception.backtrace
      clean_backtrace = exception.backtrace
      
      # strip newrelic from the trace
      clean_backtrace = clean_backtrace.reject {|line| line =~ /vendor\/plugins\/newrelic_rpm/ }
      
      # rename methods back to their original state
      clean_backtrace.collect {|line| line.gsub "_without_(newrelic|trace)", ""}
    else
      nil
    end
  end
  
  private
  
  # Convert any kind of object to a descriptive string
  # Only call this on unknown objects.  Otherwise call to_s.
  def flatten(object)
    if object.respond_to? :inspect
      object.inspect
    elsif object.respond_to? :to_s
      object.to_s
    else
      "#<#{object.class.to_s}>"
    end
  end
  
  def truncate(string, len)
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