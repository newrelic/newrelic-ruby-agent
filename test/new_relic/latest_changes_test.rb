# frozen_string_literal: true

# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(__FILE__,'..','..','test_helper'))

module NewRelic
  class LatestChangesTest < MiniTest::Test

    def test_read_default_changelog
      result = NewRelic::LatestChanges.read
      assert_match(/# New Relic Ruby Agent Release Notes #/, result)
      assert_match(/## v\d\.\d{1,2}\.\d{1,2} ##/, result)
    end

    def test_latest_changes_from_fakechangelog
      result = NewRelic::LatestChanges.read(File.join(File.dirname(__FILE__), 'FAKECHANGELOG'))
      assert_match(/3.7.2/, result)
    end

    def test_patch_latest_changes_from_fakechangelog
      result = NewRelic::LatestChanges.read_patch('3.7.2.4242', File.join(File.dirname(__FILE__), 'FAKECHANGELOG'))
      expected = <<END
## v3.7.2.4242 ##

* Patch (3.7.2.4242)

  Patch for something
END
      assert_equal expected, result
    end

  end
end
