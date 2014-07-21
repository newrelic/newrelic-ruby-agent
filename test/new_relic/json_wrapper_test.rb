# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','test_helper'))
require 'newrelic_rpm'

class JSONWrapperTest < Minitest::Test
  def test_json_roundtrip
    obj = [
      99, 'luftballons',
      {
        'Hast du etwas' => 'Zeit für mich',
        'Dann singe ich' => {
          'ein lied' => 'für dich'
        }
      }
    ]
    copy = NewRelic::JSONWrapper.load(NewRelic::JSONWrapper.dump(obj))
    assert(obj == copy)
  end

  def test_normalize_converts_symbol_values_to_strings
    result = NewRelic::JSONWrapper.normalize([:foo, :bar])
    assert_equal(['foo', 'bar'], result)
  end

  def test_normalize_converts_symbols_in_hash_to_strings
    result = NewRelic::JSONWrapper.normalize({:key => :value})
    assert_equal({'key' => 'value'}, result)
  end

  if NewRelic::LanguageSupport.supports_string_encodings?
    def test_normalize_string_returns_input_if_correctly_encoded_utf8
      string = "i want a pony"
      result = NewRelic::JSONWrapper.normalize_string(string)
      assert_same(string, result)
      assert_equal(Encoding.find('UTF-8'), result.encoding)
    end

    def test_normalize_string_returns_munged_copy_if_ascii_8bit
      string = (0..255).to_a.pack("C*")
      result = NewRelic::JSONWrapper.normalize_string(string)
      refute_same(string, result)
      assert_equal(Encoding.find('ISO-8859-1'), result.encoding)
      assert_equal(string, result.dup.force_encoding('ASCII-8BIT'))
    end

    def test_normalize_string_returns_munged_copy_if_invalid_utf8
      string = (0..255).to_a.pack("C*").force_encoding('UTF-8')
      result = NewRelic::JSONWrapper.normalize_string(string)
      refute_same(result, string)
      assert_equal(Encoding.find('ISO-8859-1'), result.encoding)
      assert_equal(string, result.dup.force_encoding('UTF-8'))
    end

    def test_normalize_string_returns_munged_copy_if_other_convertible_encoding
      string = "i want a pony".encode('UTF-16LE')
      result = NewRelic::JSONWrapper.normalize_string(string)
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
      result = NewRelic::JSONWrapper.normalize_string(string)
      refute_same(result, string)
      assert_equal(Encoding.find('ISO-8859-1'), result.encoding)
      assert_equal('Jyv+AOQ-skyl+AOQ-'.force_encoding('ISO-8859-1'), result)
    end

    def test_normalizes_string_encodings_if_asked
      string = (0..255).to_a.pack("C*")
      encoded = NewRelic::JSONWrapper.dump([string], :normalize => true)
      decoded = NewRelic::JSONWrapper.load(encoded)
      expected = [string.dup.force_encoding('ISO-8859-1').encode('UTF-8')]
      assert_equal(expected, decoded)
    end
  end
end
