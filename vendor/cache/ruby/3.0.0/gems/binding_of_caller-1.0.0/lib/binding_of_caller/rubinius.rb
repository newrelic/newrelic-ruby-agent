module BindingOfCaller
  module BindingExtensions

    # Retrieve the binding of the nth caller of the current frame.
    # @return [Binding]
    def of_caller(n)
      location = Rubinius::VM.backtrace(1 + n, true).first

      raise RuntimeError, "Invalid frame, gone beyond end of stack!" if location.nil?

      setup_binding_from_location(location)
    end

    # The description of the frame.
    # @return [String]
    def frame_description
      @frame_description
    end

    # Return bindings for all caller frames.
    # @return [Array<Binding>]
    def callers
      Rubinius::VM.backtrace(1, true).map &(method(:setup_binding_from_location).
                                            to_proc)
    end

    # Number of parent frames available at the point of call.
    # @return [Fixnum]
    def frame_count
      Rubinius::VM.backtrace(1).count
    end

    # The type of the frame.
    # @return [Symbol]
    def frame_type
      if compiled_code.for_module_body?
        :class
      elsif compiled_code.for_eval?
        :eval
      elsif compiled_code.is_block?
        :block
      else
        :method
      end
    end

    protected

    def setup_binding_from_location(location)
      binding = Binding.setup location.variables,
                              location.variables.method,
                              location.constant_scope,
                              location.variables.self,
                              location

      binding.instance_variable_set :@frame_description,
                                   location.describe.gsub("{ } in", "block in")

      binding
    end
  end
end

class ::Binding
  include BindingOfCaller::BindingExtensions
  extend BindingOfCaller::BindingExtensions
end
