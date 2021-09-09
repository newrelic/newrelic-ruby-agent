module Hometown
  class DisposalTracer
    attr_reader :undisposed, :untraced_disposals

    def initialize
      @tracing_classes = {}

      @undisposed         = Hash.new(0)
      @untraced_disposals = Hash.new(0)
    end

    def patch(clazz, disposal_method)
      return if @tracing_classes.include?(clazz)
      @tracing_classes[clazz] = true

      trace_creation(clazz)
      patch_disposal_method(clazz, disposal_method)
    end

    def trace_creation(clazz)
      Hometown.creation_tracer.patch(clazz, method(:mark_for_disposal))
    end

    def patch_disposal_method(clazz, disposal_method)
      traced   = "#{disposal_method}_traced"
      untraced = "#{disposal_method}_untraced"

      clazz.class_eval do
        define_method(traced) do |*args, &blk|
          Hometown.disposal_tracer.notice_disposed(self)
          self.send(untraced, *args, &blk)
        end

        alias_method untraced, disposal_method
        alias_method disposal_method, traced
      end
    end

    def mark_for_disposal(instance)
      trace = Hometown.for(instance)
      @undisposed[trace] += 1
    end

    def notice_disposed(instance)
      trace = Hometown.for(instance)
      if trace
        @undisposed[trace] -= 1
      else
        trace = Trace.new(instance.class, caller)
        @untraced_disposals[trace] += 1
      end
    end

    UNDISPOSED_HEADING = "Undisposed Resources"
    UNTRACED_HEADING   = "Untraced Disposals"
    UNDISPOSED_TOTALS_HEADING = "Undisposed Totals"
    UNTRACED_TOTALS_HEADING   = "Untraced Disposals Totals"

    def undisposed_report
      result  = format_trace_hash(UNDISPOSED_HEADING, @undisposed)
      result += format_trace_hash(UNTRACED_HEADING, @untraced_disposals)

      result += format_totals(UNDISPOSED_TOTALS_HEADING, @undisposed)
      result += format_totals(UNTRACED_TOTALS_HEADING, @untraced_disposals)

      result
    end

    def format_trace_hash(heading, hash)
      result = ""
      hash.each do |trace, count|
        if count > 0
          result += "[#{trace.traced_class}] => #{count}\n"
          result += "\t#{trace.backtrace.join("\n\t")}\n\n"
        end
      end

      add_heading_if_needed(heading, result)
    end

    def format_totals(heading, hash)
      result = ""
      hash.group_by { |trace, _| trace.traced_class }.each do |clazz, counts|
        count = counts.map { |count| count.last }.inject(0, &:+)
        if count > 0
          result += "[#{clazz}] => #{count}\n"
        end
      end

      add_heading_if_needed(heading, result)
    end

    def add_heading_if_needed(heading, result)
      if result.empty?
        ""
      else
        "#{heading}:\n#{result}"
      end
    end
  end
end
