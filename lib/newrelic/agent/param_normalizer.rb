module ParamNormalizer
  # Transform parameter hash into a hash whose values are strictly
  # strings
  def normalize_params(params)
    case params
      when Symbol, Numeric, FalseClass, TrueClass:
        params
      when String
        truncate(params, 256)
      when Hash:
        new_params = {}
        params.each do | key, value |
          new_params[truncate(key,32)] = normalize_params(value)
        end
        new_params
      when Enumerable:
        params.first(20).collect { | v | normalize_params(v)}
      else
        if params.respond_to? :inspect
          v = params.inspect
        elsif params.respond_to? :to_s
          v = params.to_s
        else
          v = "#<#{params.class.to_s}>"
        end
        normalize_params(v)
    end
  end
  private 
  def truncate(string, len)
    string.to_s.gsub(/^(.{#{len}})(.*)/) {$2.blank? ? $1 : $1 + "..."}
  end
end