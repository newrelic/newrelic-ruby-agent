class NewRelic::MetricParser::Controller < NewRelic::MetricParser
  
  def is_controller?
    true
  end
  
  def controller_name
    segments[1..-2].join('/').camelize+"Controller"
  end

  def action_name
    if segments[-1] =~ /^\(other\)$/
      '(template only)'
    else
      segments[-1]
    end
  end
  
  def developer_name
    "#{controller_name}##{action_name}"
  end
  
  # return the cpu measuring equivalent.  It may be nil since this metric was not
  # present in earlier versions of the agent.
  def cpu_metric
    Metric.lookup((["ControllerCPU"] + segments[1..-1]).join('/'), :create => false)
  end
  
  def short_name
    # standard controller actions
    if segments.length > 1
      url
    else
      'All Controller Actions'
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