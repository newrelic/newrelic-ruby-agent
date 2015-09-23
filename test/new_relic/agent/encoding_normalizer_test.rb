# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..', '..','test_helper'))
require 'new_relic/agent/encoding_normalizer.rb'

class EncodingNormalizerTest < Minitest::Test
  EncodingNormalizer = NewRelic::Agent::EncodingNormalizer

  def test_normalize_object_converts_symbol_values_to_strings
    result = EncodingNormalizer.normalize_object([:foo, :bar])
    assert_equal(['foo', 'bar'], result)
  end

  def test_normalize_object_converts_symbols_in_hash_to_strings
    result = EncodingNormalizer.normalize_object({:key => :value})
    assert_equal({'key' => 'value'}, result)
  end

  def test_normalize_object_converts_rationals_to_floats
    result = EncodingNormalizer.normalize_object({:key => Rational(3,2)})
    assert_equal({'key' => 1.5}, result)
  end

  if NewRelic::LanguageSupport.supports_string_encodings?
    def test_normalize_string_returns_input_if_correctly_encoded_utf8
      string = "i want a pony"
      result = EncodingNormalizer.normalize_string(string)
      assert_same(string, result)
      assert_equal(Encoding.find('UTF-8'), result.encoding)
    end

    def test_normalize_string_returns_munged_copy_if_ascii_8bit
      string = (0..255).to_a.pack("C*")
      result = EncodingNormalizer.normalize_string(string)
      refute_same(string, result)
      assert_equal(Encoding.find('ISO-8859-1'), result.encoding)
      assert_equal(string, result.dup.force_encoding('ASCII-8BIT'))
    end

    def test_normalize_string_returns_munged_copy_if_invalid_utf8
      string = (0..255).to_a.pack("C*").force_encoding('UTF-8')
      result = EncodingNormalizer.normalize_string(string)
      refute_same(result, string)
      assert_equal(Encoding.find('ISO-8859-1'), result.encoding)
      assert_equal(string, result.dup.force_encoding('UTF-8'))
    end

    def test_normalize_string_returns_munged_copy_if_other_convertible_encoding
      string = "i want a pony".encode('UTF-16LE')
      result = EncodingNormalizer.normalize_string(string)
      refute_same(result, string)
      assert_equal(Encoding.find('UTF-8'), result.encoding)
      assert_equal(string, result.encode('UTF-16LE'))
    end

    def test_normalize_string_returns_munged_copy_if_other_non_convertible_enocding
      # Attempting to convert from UTF-7 to UTF-8 in Ruby will raise an
      # Encoding::ConverterNotFoundError, which is what we're trying to
      # replicate for this test case.
      # The following UTF-7 string decodes to 'Jyväskylä', a city in Finland
      string = "Jyv+AOQ-skyl+AOQ-".force_encoding("UTF-7")
      assert string.valid_encoding?
      result = EncodingNormalizer.normalize_string(string)
      refute_same(result, string)
      assert_equal(Encoding.find('ISO-8859-1'), result.encoding)
      assert_equal('Jyv+AOQ-skyl+AOQ-'.force_encoding('ISO-8859-1'), result)
    end
  end
end
