# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.


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

    def instance_methods_include?(klass, method_name)
      method_name_sym = method_name.to_sym
      (
        klass.instance_methods.map{ |s| s.to_sym }.include?(method_name_sym)          ||
        klass.protected_instance_methods.map{ |s|s.to_sym }.include?(method_name_sym) ||
        klass.private_instance_methods.map{ |s|s.to_sym }.include?(method_name_sym)
      )
    end

    def time_to_millis(time)
      (time.to_f * 1000).round
    end

    def milliseconds_to_seconds(milliseconds)
      milliseconds / 1000.0
    end
  end

  # Load the JSON library from the standard library.
  def self::load_stdlib_json
    return false unless NewRelic::LanguageSupport.stdlib_json_usable?

    require 'json'
    define_method( :json_dump, &::JSON.method(:dump) )
    define_method( :json_load, &::JSON.method(:parse) )

    return true
  rescue LoadError
    NewRelic::Agent.logger.debug "%p while loading JSON library: %s" % [ err, err.message ] if
      defined?( NewRelic::Agent ) && NewRelic::Agent.respond_to?( :logger )
    return false
  end


  # Load the fallback JSON library
  def self::load_okjson
    require 'new_relic/okjson'
    define_method( :json_dump, &::NewRelic::OkJson.method(:encode) )
    define_method( :json_load, &::NewRelic::OkJson.method(:decode) )
  end


  load_stdlib_json or load_okjson
  module_function :json_dump, :json_load

end
