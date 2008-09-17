module ParamNormalizer
  # Transform parameter hash into a hash whose values are strictly
  # strings
  def normalize_params(params)
    case params
      when Numeric, String, Symbol, FalseClass, TrueClass:
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
        normalize_params(params.inspect)
    end
  end
  private 
  def truncate(string, len)
    string.to_s.gsub(/^(.{#{len}})(.*)/) {$2.blank? ? $1 : $1 + "..."}
  end
end