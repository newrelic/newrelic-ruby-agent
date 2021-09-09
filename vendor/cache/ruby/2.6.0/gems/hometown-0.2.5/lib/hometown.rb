require "hometown/creation_tracer"
require "hometown/disposal_tracer"
require "hometown/trace"
require "hometown/version"

module Hometown
  @creation_tracer = Hometown::CreationTracer.new
  @disposal_tracer = Hometown::DisposalTracer.new

  class << self
    attr_accessor :creation_tracer, :disposal_tracer
  end

  def self.watch(clazz)
    @creation_tracer.patch(clazz)
  end

  def self.watch_for_disposal(clazz, disposal_method)
    @disposal_tracer.patch(clazz, disposal_method)
  end

  def self.for(instance)
    @creation_tracer.find_trace_for(instance)
  end

  def self.undisposed
    @disposal_tracer.undisposed
  end

  def self.undisposed_report
    @disposal_tracer.undisposed_report
  end

  def self.undisposed_report_at_exit
    at_exit do
      report = Hometown.undisposed_report
      report = "No leaks? Nice work!" if report.empty?
      puts report
    end
  end
end
