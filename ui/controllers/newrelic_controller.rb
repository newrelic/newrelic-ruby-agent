require 'newrelic/agent'
require 'google_pie_chart'
require 'active_record'
require 'transaction_analysis'

class NewrelicController < ActionController::Base
  include NewrelicHelper
  
  # for this controller, the views are located in a different directory from
  # the application's views.
  view_path = File.join(File.dirname(__FILE__), '..', 'views')
  if public_methods.include? "view_paths"   # rails 2.0+
    self.view_paths << view_path
  else                                      # rails <2.0
    self.template_root = view_path
  end
  
  layout "default"
  
  write_inheritable_attribute('do_not_trace', true)
  
  def index
    get_samples
  end
  
  def view_sample
    get_sample
    
    unless @sample
      render :action => "sample_not_found" 
      return
    end

    # TODO move to a helper
    @pie_chart = GooglePieChart.new
    @pie_chart.color = '6688AA'
    
    chart_data = @sample.breakdown_data(6)
    chart_data.each { |s| @pie_chart.add_data_point s.metric_name, s.exclusive_time.to_ms }
  end
  
  def explain_sql
    get_segment

    @sql = @segment[:sql]
    @explanation = []
    @trace = @segment[:backtrace]
    
    result = ActiveRecord::Base.connection.execute("EXPLAIN #{@sql}")
    @explanation = []
    result.each {|row| @explanation << row }
    
    # @explanation = ActiveRecord::Base.connection.select_rows("EXPLAIN #{@sql}")
    @row_headers = [
      nil,
      "Select Type",
      "Table",
      "Type",
      "Possible Keys",
      "Key",
      "Key Length",
      "Ref",
      "Rows",
      "Extra"
    ];
      
  end
  
private 
  
  def get_samples
    @samples = NewRelic::Agent.instance.transaction_sampler.get_samples.select do |sample|
      sample.params[:path] != nil
    end
    
    @samples = @samples.reverse
  end
  
  def get_sample
    get_samples
    sample_id = params[:id].to_i
    @samples.each do |s|
      if s.sample_id == sample_id
        @sample = stripped_sample(s)
        return 
      end
    end
  end
  
  def get_segment
    get_sample
    return unless @sample
    
    segment_id = params[:segment].to_i
    @sample.each_segment do |s|
      if s.segment_id == segment_id
        @segment = s
        return
      end
    end
  end
end


