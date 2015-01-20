# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(__FILE__,'..','..','test_helper'))

module NewRelic
  class LatestChangesTest < MiniTest::Test
    def setup
      # 1.8.7 returns relative paths for __FILE__. test:env environment then
      # can't find the CHANGELOG since current dir is test app instead of gem.
      #
      # This doesn't impact production usage of NewRelic::LatestChanges on
      # the gem post-installation, since that's run in our gem's context. So
      # just fix up the pathing in the test for finding default changelog.
      if RUBY_VERSION < '1.9.1'
        NewRelic::LatestChanges.stubs(:default_changelog).returns(File.join(File.dirname(__FILE__), '..', '..', 'CHANGELOG'))
      end
    end

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
