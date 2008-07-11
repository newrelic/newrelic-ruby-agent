require 'pathname'

module NewrelicHelper
  
  # return the host that serves static content (css, metric documentation, images, etc)
  # that supports the desktop edition.
  def server
    NewRelic::Agent.instance.config['desktop_server'] || "http://rpm.newrelic.com"
  end
  
  # return the sample but post processed to strip out segments that normally don't show
  # up in production (after the first execution, at least) such as application code loading
  def stripped_sample(sample = @sample)
    if session[:newrelic_strip_code_loading] || true
      sample.omit_segments_with('(Rails/Application Code Loading)|(Database/.*/.+ Columns)')
    else
      sample
    end
  end
  
  # return the highest level in the call stack for the trace that is not rails or 
  # newrelic agent code
  def application_caller(trace)
    trace.each do |trace_line|
      file = file_and_line(trace_line).first
      unless exclude_file_from_stack_trace?(file, false)
        return trace_line
      end
    end
    trace.last
  end
  
  def application_stack_trace(trace, include_rails = false)
    trace.reject do |trace_line|
      file = file_and_line(trace_line).first
      exclude_file_from_stack_trace?(file, include_rails)
    end
  end
  
  def url_for_metric_doc(metric_name)
    "#{server}/metric_doc?metric=#{CGI::escape(metric_name)}"
  end
  
  def url_for_source(trace_line)
    file, line = file_and_line(trace_line)
    
    begin
      file = Pathname.new(file).realpath
    rescue Errno::ENOENT
      # we hit this exception when Pathame.realpath fails for some reason; attempt a link to
      # the file without a real path.  It may also fail, only when the user clicks on this specific
      # entry in the stack trace
    rescue 
      # catch all other exceptions.  We're going to create an invalid link below, but that's okay.
    end
      
    if using_textmate?
      "txmt://open?url=file://#{file}&line=#{line}"
    else
      url_for :action => 'show_source', :file => file, :line => line, :anchor => 'selected_line'
    end
  end
  
  def link_to_source(trace)
    image_url = "#{server}/images/"
    image_url << (using_textmate? ? "textmate.png" : "file_icon.png")
    
    link_to image_tag(image_url), url_for_source(application_caller(trace))
  end
  
  def timestamp(segment)
    sprintf("%1.3f", segment.entry_timestamp)
  end
  
  def format_timestamp(time)
    time.strftime("%H:%M:%S") 
  end

  def colorize(value, yellow_threshold = 0.05, red_threshold = 0.15)
    if value > yellow_threshold
      color = (value > red_threshold ? 'red' : 'orange')
      "<font color=#{color}>#{value.to_ms}</font>"
    else
      "#{value.to_ms}"
    end
  end
  
  def explain_sql_url(segment)
    url_for(:action => :explain_sql, 
      :id => @sample.sample_id, 
      :segment => segment.segment_id)
  end
  
  def line_wrap_sql(sql)
    sql.gsub(/\,/,', ').squeeze(' ')
  end
  
  def render_sample_details(sample)
    # skip past the root segments to the first child, which is always the controller
    render_segment_details sample.root_segment.called_segments.first
  end

  # the rows logger plugin disables the sql tracing functionality of the NewRelic agent -
  # notify the user about this
  def rows_logger_present?
    File.exist?(File.join(File.dirname(__FILE__), "../../../rows_logger/init.rb"))
  end
  
private
  def file_and_line(stack_trace_line)
    stack_trace_line.match(/(.*):(\d+)/)[1..2]
  end
  
  def using_textmate?
    # For now, disable textmate integration
    false
  end
  
  def render_segment_details(segment, depth=0)
    html = render(:partial => "segment", :object => segment, :locals => {:indent => depth})
    
    segment.called_segments.each do |child|
      html << render_segment_details(child, depth+1)
    end
    
    html
  end
  
  def exclude_file_from_stack_trace?(file, include_rails)
    is_agent = file =~ /\/newrelic\/agent\//
    return is_agent if include_rails
    
    is_agent ||
      file =~ /\/active(_)*record\// ||
      file =~ /\/action(_)*controller\// ||
      file =~ /\/activesupport\// ||
      file =~ /\/actionpack\//
  end
end
