module BindingOfCaller
  class JRubyBindingHolder
    java_import org.jruby.RubyBinding

    def initialize(binding)
      @binding = binding
    end

    def eval(code, file = nil, line = nil)
      b = JRuby.dereference(RubyBinding.new(JRuby.runtime, Binding, @binding))
      if (file == nil)
        Kernel.eval code, b
      else
        Kernel.eval code, b, file, line
      end
    end

    def frame_type
      case
        when block?
          :block
        when eval?
          :eval
        when top?
          :top
        else
          :method
      end
    end

    def frame_description
      "#{block_desc}#{method_desc}"
    end

    private

    def block?
      @binding.getDynamicScope().getStaticScope().isBlockScope()
    end

    def eval?
      @binding.getFrame().getKlazz().nil? && @binding.getLine() != 0
    end

    def top?
      @binding.getFrame().getKlazz().nil? && @binding.getLine() == 0
    end

    def block_desc
      if frame_type == :block
        "block in "
      end
    end

    def method_desc
      @binding.getFrame().getName() || "<main>"
    end
  end

  module BindingExtensions
    def of_caller(index = 1)
      index += 1 # always omit this frame
      JRuby.runtime.current_context.binding_of_caller(index)
    end

    def callers
      ary = []
      n = 2
      while binding = of_caller(n)
        ary << binding
        n += 1
      end
      ary
    end

    def frame_count
      callers.count - 1
    end

    def frame_type
      nil
    end

    def frame_description
      nil
    end
  end
end


class org::jruby::runtime::ThreadContext
  java_import org.jruby.runtime.Binding
  java_import org.jruby.RubyInstanceConfig::CompileMode

  field_accessor :frameStack, :frameIndex,
                 :scopeStack, :scopeIndex,
                 :backtrace, :backtraceIndex

  def binding_of_caller(index)
    unless JRuby.runtime.instance_config.compile_mode == CompileMode::OFF
      raise RuntimeError, "caller binding only supported in interpreter"
    end

    index += 1 # always omit this frame

    return nil if index > frameIndex

    frame = frameStack[frameIndex - index]

    return binding_of_caller(index - 1) if index > scopeIndex

    scope = scopeStack[scopeIndex - index]
    element = backtrace[backtraceIndex - index]

    binding = Binding.new(frame, scope.static_scope.module, scope, element.clone)

    BindingOfCaller::JRubyBindingHolder.new(binding)
  end
end

class ::Binding
  include BindingOfCaller::BindingExtensions
end