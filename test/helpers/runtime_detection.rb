# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module TestHelpers
    module RuntimeDetection
      def rubinius?
        defined?(RUBY_ENGINE) && RUBY_ENGINE == 'rbx'
      end

      def jruby?
        defined?(JRuby)
      end
    end
  end
end
