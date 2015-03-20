# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# This module was extracted from NewRelic::JSONWrapper

module NewRelic
  module Agent
    module EncodingNormalizer
      def self.normalize_string(s)
        @normalizer ||= choose_normalizer
        @normalizer.normalize(s)
      end

      def self.normalize_object(object)
        case object
        when String
          normalize_string(object)
        when Symbol
          normalize_string(object.to_s)
        when Array
          return object if object.empty?
          result = object.map { |x| normalize_object(x) }
          result
        when Hash
          return object if object.empty?
          hash = {}
          object.each_pair do |k, v|
            k = normalize_string(k)      if k.is_a?(String)
            k = normalize_string(k.to_s) if k.is_a?(Symbol)
            hash[k] = normalize_object(v)
          end
          hash
        else
          object
        end
      end

      def self.choose_normalizer
        if NewRelic::LanguageSupport.supports_string_encodings?
          EncodingNormalizer
        else
          IconvNormalizer
        end
      end

      module EncodingNormalizer
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

      module IconvNormalizer
        def self.normalize(s)
          if @iconv.nil?
            require 'iconv'
            @iconv = Iconv.new('utf-8', 'iso-8859-1')
          end
          @iconv.iconv(s)
        end
      end
    end
  end
end