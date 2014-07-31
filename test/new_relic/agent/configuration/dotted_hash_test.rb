# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

module NewRelic::Agent::Configuration
  class DottedHashTest < Minitest::Test
    def test_without_nesting
      hash = DottedHash.new({ :turtle => 1 })
      assert_equal({ :turtle => 1 }, hash)
    end

    def test_with_nesting
      hash = DottedHash.new({ :turtle => { :turtle => 1 } })
      assert_equal({ :'turtle.turtle' => 1 }, hash)
    end

    def test_with_multiple_layers_of_nesting
      hash = DottedHash.new({ :turtle => { :turtle => { :turtle => 1 } } })
      assert_equal({ :'turtle.turtle.turtle' => 1 }, hash)
    end

    def test_turns_keys_to_symbols
      hash = DottedHash.new({ "turtle" => { "turtle" => { "turtle" => 1 } } })
      assert_equal({ :'turtle.turtle.turtle' => 1 }, hash)
    end

    def test_to_hash
      dotted = DottedHash.new({ "turtle" => { "turtle" => { "turtle" => 1 } } })
      hash = dotted.to_hash

      assert_instance_of(Hash, hash)
      assert_equal({ :'turtle.turtle.turtle' => 1 }, hash)
    end

    def test_option_to_keep_nesting
      hash = DottedHash.new({ :turtle => { :turtle => 1 } }, true)
      expected = {
        :turtle => { :turtle => 1},
        :'turtle.turtle' => 1,
      }

      assert_equal(expected, hash)
    end

    def test_borks_with_non_symbolizing_key
      assert_raises(NoMethodError) do
        DottedHash.new({ Object.new => 2 }, true)
      end
    end
  end
end
