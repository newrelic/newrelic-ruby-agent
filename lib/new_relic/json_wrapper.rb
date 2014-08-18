# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  class JSONWrapper
    def self.load_native_json
      begin
        require 'json' unless defined?(::JSON)
        @load_method = ::JSON.method(:load)
        @dump_method = ::JSON.method(:dump)
        @backend_name = :json
        return true
      rescue StandardError, ScriptError
        NewRelic::Agent.logger.debug "%p while loading JSON library: %s" % [ err, err.message ] if
          defined?( NewRelic::Agent ) && NewRelic::Agent.respond_to?( :logger )
      end
    end

    def self.load_okjson
      require 'new_relic/okjson'
      @load_method = ::NewRelic::OkJson.method(:decode)
      @dump_method = ::NewRelic::OkJson.method(:encode)
      @backend_name = :okjson
    end

    load_native_json or load_okjson

    def self.usable_for_collector_serialization?
      @backend_name == :json
    end

    def self.backend_name
      @backend_name
    end

    def self.normalize_string(s)
      choose_normalizer unless @normalizer
      @normalizer.normalize(s)
    end

    def self.choose_normalizer
      if NewRelic::LanguageSupport.supports_string_encodings?
        @normalizer = EncodingNormalizer
      else
        @normalizer = IconvNormalizer
      end
    end

    class EncodingNormalizer
      def self.normalize(s)
        encoding = s.encoding
        if (encoding == Encoding::UTF_8 || encoding == Encoding::ISO_8859_1) && s.valid_encoding?
          return s
        end

        # If the encoding is not valid, or it's ASCII-8BIT, we know conversion to
        # UTF-8 is likely to fail, so treat it as ISO-8859-1 (byte-preserving).
        normalized = s.dup
        if encoding == Encoding::ASCII_8BIT || !s.valid_encoding?
          normalized.force_encoding(Encoding::ISO_8859_1)
        else
          # Encoding is valid and non-binary, so it might be cleanly convertible
          # to UTF-8. Give it a try and fall back to ISO-8859-1 if it fails.
          begin
            normalized.encode!(Encoding::UTF_8)
          rescue
            normalized.force_encoding(Encoding::ISO_8859_1)
          end
        end
        normalized
      end
    end

    class IconvNormalizer
      def self.normalize(s)
        if @iconv.nil?
          require 'iconv'
          @iconv = Iconv.new('utf-8', 'iso-8859-1')
        end
        @iconv.iconv(s)
      end
    end

    def self.normalize(object)
      case object
      when String
        normalize_string(object)
      when Symbol
        normalize_string(object.to_s)
      when Array
        return object if object.empty?
        result = object.map { |x| normalize(x) }
        result
      when Hash
        return object if object.empty?
        hash = {}
        object.each_pair do |k, v|
          k = normalize_string(k)      if k.is_a?(String)
          k = normalize_string(k.to_s) if k.is_a?(Symbol)
          hash[k] = normalize(v)
        end
        hash
      else
        object
      end
    end

    def self.supports_normalization?
      NewRelic::LanguageSupport.supports_string_encodings?
    end

    def self.dump(object, options={})
      object = normalize(object) if options[:normalize]
      @dump_method.call(object)
    end

    def self.load(string)
      @load_method.call(string)
    end
  end
end
