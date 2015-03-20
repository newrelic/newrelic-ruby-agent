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

  if NewRelic::LanguageSupport.supports_string_encodings?
    def test_normalizes_string_encodings_if_asked
      string = (0..255).to_a.pack("C*")
      encoded = NewRelic::JSONWrapper.dump([string], :normalize => true)
      decoded = NewRelic::JSONWrapper.load(encoded)
      expected = [string.dup.force_encoding('ISO-8859-1').encode('UTF-8')]
      assert_equal(expected, decoded)
    end
  end
end
