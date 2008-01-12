module NewrelicHelper
  
  # return the sample but post processed to strip out segments that normally don't show
  # up in production (after the first execution, at least) such as application code loading
  def stripped_sample(sample = @sample)
    if session[:newrelic_strip_code_loading] || true
      sample.omit_segments_with('(Rails/Application Code Loading)|(Database/.*/.+ Columns)')
    else
      sample
    end
  end
end
