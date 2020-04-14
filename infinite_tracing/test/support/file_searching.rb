# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module TestHelpers
    module FileSearching
      def all_rb_files
        pattern = File.expand_path(gem_root + "/**/*.{rb,rhtml}")
        Dir[pattern]
      end

      def all_rb_and_js_files
        pattern = File.expand_path(gem_root + "/**/*.{rb,js}")
        Dir[pattern]
      end

      def all_files
        pattern = File.expand_path(gem_root + "/**/*")
        Dir[pattern]
      end

      def gem_root
        File.expand_path(File.dirname(__FILE__) + "/../../")
      end
    end
  end
end
