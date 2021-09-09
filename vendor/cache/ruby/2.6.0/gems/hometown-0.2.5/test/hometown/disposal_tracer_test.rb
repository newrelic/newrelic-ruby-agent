require File.expand_path(File.join(File.dirname(__FILE__), "..", "test_helper"))
require 'hometown'
require 'hometown/disposal_tracer'

module Hometown
  class DisposalTracerTest < Minitest::Test
    def setup
      @tracer = DisposalTracer.new
      @original_tracer = Hometown.disposal_tracer
      Hometown.disposal_tracer = @tracer
    end

    def teardown
      Hometown.disposal_tracer = @original_tracer
    end

    def test_empty_report
      assert_empty @tracer.undisposed_report
    end

    def test_traces_disposal
      clazz = new_class
      @tracer.patch(clazz, :dispose)

      instance = clazz.new
      trace = Hometown.for(instance)
      assert_equal 1, @tracer.undisposed[trace]

      instance.dispose
      assert_equal 0, @tracer.undisposed[trace]
    end

    def test_undisposed_report
      clazz = new_class
      @tracer.patch(clazz, :dispose)

      instance = clazz.new
      report = @tracer.undisposed_report

      assert_match DisposalTracer::UNDISPOSED_HEADING, report
      assert_match DisposalTracer::UNDISPOSED_TOTALS_HEADING, report
      assert_match clazz.to_s, report
      assert_match __FILE__, report
      assert_match /#{clazz.to_s}.*1/, report
    end

    def test_empty_report_if_all_disposed
      clazz = new_class
      @tracer.patch(clazz, :dispose)

      instance = clazz.new
      instance.dispose

      assert_empty @tracer.undisposed_report
    end

    def test_safely_disposes_already_created_objects
      clazz = new_class
      instance = clazz.new
      @tracer.patch(clazz, :dispose)

      instance.dispose

      assert_empty @tracer.undisposed
      assert_equal 1, @tracer.untraced_disposals.count
    end

    def test_untraced_disposals_show_up_in_report
      clazz = new_class
      instance = clazz.new
      @tracer.patch(clazz, :dispose)

      instance.dispose
      report = @tracer.undisposed_report

      assert_match DisposalTracer::UNTRACED_HEADING, report
      assert_match DisposalTracer::UNTRACED_TOTALS_HEADING, report
      assert_match clazz.to_s, report
      assert_match __FILE__, report
      assert_match /#{clazz.to_s}.*1/, report
    end

    def new_class
      Class.new do
        define_method(:dispose) do
        end
      end
    end
  end
end
