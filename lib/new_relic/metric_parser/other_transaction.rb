# OtherTransaction metrics must have at least three segments: /OtherTransaction/<job type>/*

class NewRelic::MetricParser::OtherTransaction < NewRelic::MetricParser
  def job_type
    segments[1]
  end
  
  def developer_name
    segments[2..-1].join(NewRelic::MetricParser::SEPARATOR)
  end
end