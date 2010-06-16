class NewRelic::MetricParser::Apdex < NewRelic::MetricParser
  
  CLIENT = 'Client'
  
  # Convenience method for creating the appropriate client
  # metric name.
  def self.client_metric(apdex_t)
    "Apdex/#{CLIENT}/#{apdex_t}"
  end
  
  def is_client?
    segments[1] == CLIENT
  end
  def is_summary?
    segments.size == 1
  end
  
  # Apdex/Client/N
  def apdex_t
    is_client? && segments[2].to_f
  end
  
  def developer_name
    case
      when is_client? then "Apdex Client (#{apdex_t})"
      when is_summary? then "Apdex"
      else "Apdex #{segments[1..-1].join("/")}"
    end
  end
  
  def short_name
    # standard controller actions
    if segments.length > 1
      url
    else
      'All Frontend Urls'
    end
  end
  
  def url
    '/' + segments[1..-1].join('/')
  end
  
  # this is used to match transaction traces to controller actions.  
  # TT's don't have a preceding slash :P
  def tt_path
    segments[1..-1].join('/')
  end

  def call_rate_suffix
    'rpm'
  end
end