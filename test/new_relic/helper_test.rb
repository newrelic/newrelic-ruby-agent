# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','test_helper'))
require 'test/unit'
require 'newrelic_rpm'

if RUBY_VERSION > '1.8.6'

class HelperTest < Test::Unit::TestCase

  def test_json_serializer_method
    obj = [
      99, 'luftballons',
      {
        'Hast du etwas' => 'Zeit für mich',
        'Dann singe ich' => {
          'ein lied' => 'für dich'
        }
      }
    ]
    copy = NewRelic.json_load( NewRelic.json_dump(obj) )

    assert( obj == copy )
  end

end

else
  puts "Skipping tests in #{__FILE__} because 1.8.6 character encoding is, um, less than stellar"
end
