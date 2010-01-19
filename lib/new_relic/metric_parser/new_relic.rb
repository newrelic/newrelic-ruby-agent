class NewRelic::MetricParser::NewRelic < NewRelic::MetricParser
  def short_name
    segments.last
  end

  def above_tail
    segments[-2]
  end
end