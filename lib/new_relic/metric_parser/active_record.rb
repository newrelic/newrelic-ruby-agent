module NewRelic::MetricParser::ActiveRecord
  def is_active_record? ; true; end
  
  def model_class
    return segments[1]
  end
  
  def developer_name
    "#{model_class}##{segments.last}"
  end
end