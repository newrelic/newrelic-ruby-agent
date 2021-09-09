require File.expand_path(File.join(File.dirname(__FILE__), "test_helper"))
require 'hometown'

class HometownTest < Minitest::Test
  class Traced
  end

  class Untraced
  end

  class SubclassOfTraced < Traced
  end

  class TracedWithBlock
    def initialize(&blk)
      blk.call
    end
  end

  class Disposable
    def dispose
    end
  end

  class DisposableArguments
    def dispose(a,b,c)
      if block_given?
        yield a, b, c
      else
        [a,b,c]
      end
    end
  end

  def teardown
    Hometown.undisposed.clear
  end

  def test_untraced_class
    traced_object = Untraced.new
    assert_nil Hometown.for(traced_object)
  end

  def test_tracing_includes_classname
    Hometown.watch(Traced)
    traced_object = Traced.new

    result = Hometown.for(traced_object)
    assert_equal Traced, result.traced_class
  end

  def test_tracing_extends_to_subclasses
    Hometown.watch(Traced)
    traced_object = SubclassOfTraced.new

    result = Hometown.for(traced_object)
    assert_equal SubclassOfTraced, result.traced_class
  end

  def test_tracing_includes_this_file
    Hometown.watch(Traced)
    traced_object = Traced.new

    result = Hometown.for(traced_object)
    assert_includes result.backtrace.join("\n"), __FILE__
  end

  def test_initialize_with_block
    Hometown.watch(TracedWithBlock)
    traced_object = TracedWithBlock.new do
      i = 1
    end

    result = Hometown.for(traced_object)
    assert_equal TracedWithBlock, result.traced_class
  end

  def test_class_with_overridden_new
    Hometown.watch(::Thread)
    thread = Thread.new { sleep 1 }

    result = Hometown.for(thread)
    assert_equal ::Thread, result.traced_class
  end

  def test_doesnt_mark_for_disposal
    Hometown.watch(TracedWithBlock)
    traced_object = TracedWithBlock.new do
      i = 1
    end

    result = Hometown.undisposed
    trace = Hometown.for(traced_object)
    assert_equal 0, result[trace]
  end

  def test_marks_for_disposal
    Hometown.watch_for_disposal(Disposable, :dispose)
    dispose = Disposable.new

    result = Hometown.undisposed
    trace = Hometown.for(dispose)
    assert_equal 1, result[trace]
  end

  def test_multiples_marked_for_disposal
    Hometown.watch_for_disposal(Disposable, :dispose)
    latest_disposed = nil
    2.times do
      latest_disposed = Disposable.new
    end

    result = Hometown.undisposed
    trace = Hometown.for(latest_disposed)
    assert_equal 2, result[trace]
  end

  def test_actually_disposing
    Hometown.watch_for_disposal(Disposable, :dispose)
    dispose_me = Disposable.new

    result = Hometown.undisposed
    trace = Hometown.for(dispose_me)
    assert_equal 1, result[trace]

    dispose_me.dispose
    assert_equal 0, result[trace]
  end

  def test_actually_disposing_with_arguments
    Hometown.watch_for_disposal(DisposableArguments, :dispose)
    dispose_me = DisposableArguments.new

    result = Hometown.undisposed
    trace = Hometown.for(dispose_me)
    assert_equal 1, result[trace]

    disposable = dispose_me.dispose(1,2,3)
    assert_equal [1,2,3], disposable
    assert_equal 0, result[trace]
  end

  def test_actually_disposing_with_arguments_and_block
    Hometown.watch_for_disposal(DisposableArguments, :dispose)
    dispose_me = DisposableArguments.new

    result = Hometown.undisposed
    trace = Hometown.for(dispose_me)
    assert_equal 1, result[trace]

    disposable = dispose_me.dispose(1,2,3) do |a, b, c|
      a + b + c
    end
    assert_equal 6, disposable
    assert_equal 0, result[trace]
  end

  def test_updating_watch_for_disposal
    clazz = Class.new do
      define_method(:dispose) do
      end
    end

    Hometown.watch(clazz)
    Hometown.watch_for_disposal(clazz, :dispose)
    instance = clazz.new
    trace = Hometown.for(instance)

    result = Hometown.undisposed
    assert_equal 1, result[trace]
  end

  def test_undisposed_report
    clazz = Class.new do
      define_method(:dispose) do
      end
    end

    Hometown.watch_for_disposal(clazz, :dispose)
    instance = clazz.new

    report = Hometown.undisposed_report
    assert_kind_of String, report
    assert_includes report, clazz.to_s
    assert_includes report, __FILE__
  end
end
