module NewRelic
  # A singleton for shared generic helper methods
  module Helper
    extend self

    # confirm a string is correctly encoded (in >= 1.9)
    # If not force the encoding to ASCII-8BIT (binary)
    if RUBY_VERSION >= '1.9'
      def correctly_encoded(string)
        return string unless string.is_a? String
        string.valid_encoding? ? string : string.force_encoding("ASCII-8BIT")
      end
    else
      #noop
      def correctly_encoded(string)
        string
      end
    end

    def instance_method_visibility(klass, method_name)
      if klass.private_instance_methods.map{|s|s.to_sym}.include? method_name.to_sym
        :private
      elsif klass.protected_instance_methods.map{|s|s.to_sym}.include? method_name.to_sym
        :protected
      else
        :public
      end
    end

  end
end
