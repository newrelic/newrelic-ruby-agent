class NewRelic::MetricParser::Database < NewRelic::MetricParser
  def is_database?; true; end

  def database
    segments[1]
  end
  
  def active_record_class
    segments[2].split(' ').first
  end
  
  def operation
    op = segments.last
    op_split = op.split(' ')
    
    return op if op == 'Join Table Columns'
    op_split.last
  end
  
  def developer_name
    (segments[2]) ? "#{segments[1]} - #{segments[2]}" : "#{segments[1]} - unknown" 
  end
  
  def legend_name
    if name == Metric.DATABASE_ALL
      'Database'
    else
      super
    end
  end
  
  def tooltip_name
    if name == Metric.DATABASE_ALL
      'All Database'
    else
      super
    end
  end
end