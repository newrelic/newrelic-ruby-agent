require 'seldon/agent'

class NewRelicController < ActionController::Base
  
  # for this controller, the views are located in a different directory from
  # the application's views.
  view_path = File.join(File.dirname(__FILE__), '..', 'views')
  if public_methods.include? "view_paths"   # rails 2.0+
    self.view_paths << view_path
  else                                      # rails <2.0
    self.template_root = view_path
  end
  
  write_inheritable_attribute('do_not_trace', true)
  
  def index
    get_samples
  end
  
  def view_sample
    get_sample
    render :action => "sample_not_found" unless @sample
  end
  
private 
  
  def get_samples
    @samples = Seldon::Agent.instance.transaction_sampler.get_samples.select do |sample|
      sample.params[:path] != nil
    end
    
    @samples
  end
  
  def get_sample
    get_samples
    @samples.each do |s|
      if s.sample_id == params[:id].to_i
        @sample = s
        return
      end
    end
  end
end

# TODO move this sample analysis to a common library when we reuse it for the hosted version
class Seldon::TransactionSample
  def database_read_time
    time_percentage(/^Database\/.*\/.* Load$/)
  end
  
  def database_write_time
    time_percentage(/^Database\/.*\/.* Update$/)
  end
  
  private 
    def time_percentage(regex)
      total = 0
      each_segment do |segment|
        if regex =~ segment.metric_name
          # TODO what if a find calls something else rather than going straight to the db?
          total += segment.duration
        end
      end

      return (total / duration).to_percentage
    end
end
