module NewRelic
  module Agent
    module Instrumentation
      module GRPC
        module Helper
          def cleaned_method(method)
            method = method.to_s unless method.is_a?(String)
            return method unless method.start_with?('/')

            method[1..-1]
          end
        end
      end
    end
  end
end
