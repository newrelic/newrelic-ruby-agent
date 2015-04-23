# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/encoding_normalizer'
require 'new_relic/agent/hash_extensions'

module NewRelic
  class JSONWrapper
    def self.load_native_json
      begin
        require 'json' unless defined?(::JSON)

        # yajl's replacement methods on ::JSON override both dump and generate.
        # Because stdlib dump just calls generate, we end up calling into yajl
        # when we don't want to. As such, we use generate directly instead of
        # dump, although we have to fuss with defaults to make that ok.
        generate_method = ::JSON.method(:generate)
        if ::JSON.respond_to?(:dump_default_options)
          options = ::JSON.dump_default_options
        else
          # These were the defaults from json 1.1.9 up to 1.6.1
          options = { :allow_nan => true, :max_nesting => false }
        end
        @dump_method = Proc.new do |obj|
          generate_method.call(obj, options)
        end

        @load_method    = ::JSON.method(:load)
        @backend_name   = :json
        return true
      rescue StandardError, ScriptError => err
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

    def self.supports_normalization?
      NewRelic::LanguageSupport.supports_string_encodings?
    end

    def self.dump(object, options={})
      object = normalize(object) if options[:normalize]
      # okjson doesn't handle symbol keys, so we must stringify them before encoding
      object = Agent::HashExtensions.stringify_keys_in_object(object) if backend_name == :okjson
      @dump_method.call(object)
    end

    def self.load(string)
      @load_method.call(string)
    end

    def self.normalize_string(s)
      NewRelic::Agent::StringNormalizer.normalize_string(s)
    end

    def self.normalize(o)
      NewRelic::Agent::EncodingNormalizer.normalize_object(o)
    end
  end
end
