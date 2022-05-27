# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

unless defined?(Minitest::Test)
  Minitest::Test = MiniTest::Unit::TestCase
end

# Set up a watcher for leaking agent threads out of tests.  It'd be nice to
# disable the threads everywhere, but not all tests have newrelic.yml loaded to
# us to rely on, so instead we'll just watch for it.
class Minitest::Test
  def before_setup
    if self.respond_to?(:name)
      test_method_name = self.name
    else
      test_method_name = self.__name__
    end

    NewRelic::Agent.logger.info("*** #{self.class}##{test_method_name} **")

    super
  end
end
