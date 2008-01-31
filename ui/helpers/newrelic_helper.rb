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
  
  def sql_caller(trace)
    trace.each do |trace_line|
      file = trace_line.split(':').first
      if /activerecord/ =~ file
      elsif /newrelic\/agent/ =~ file
      else
        return trace_line
      end
    end
    trace.last
  end
  
  def trace_without_agent(trace)
    trace.reject do |trace_line|
      file = trace_line.split(':').first
      file =~ /\/newrelic\/agent\// ||
      file =~ /\/activerecord\// ||
      file =~ /\/actionpack\//
    end
  end
  
  def url_for_textmate(trace_line)
    s = trace_line.split(':')
    file = s[0]
    line = s[1]

    "txmt://open?url=file://#{file}&line=#{line}"
  end
  
  def link_to_textmate(trace)
    link_to image_tag("/images/textmate.png"), url_for_textmate(sql_caller(trace))
  end
  
  def line_wrap_sql(sql)
    sql.gsub(/\,/,', ').squeeze
  end
  
end
