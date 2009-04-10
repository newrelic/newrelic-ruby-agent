module NewRelic::MetricParser::MemCache
  def is_memcache?; true; end
  
  # for MemCache metrics, the short name is actually
  # the full name
  def short_name
    name
  end
end