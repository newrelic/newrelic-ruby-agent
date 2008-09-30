


module ParamNormalizer
  
  def normalize_params(params)
    
    result = {}
    
    params.each do |key,value|
      if !(value.is_a?(Numeric) || value.is_a?(String) || value.is_a?(Symbol))
        value = (value.respond_to?(:to_s)) ? "[#{value.class}]: #{value.to_s}" : "[#{value.class}]"
      end
      
      result[key] = value
    end
    
    result
  end
end