# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

unless defined?(Minitest::Test)
  Minitest::Test = MiniTest::Unit::TestCase
end

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

  def after_teardown
    nr_unfreeze_time
    nr_unfreeze_process_time
    super
  end
end
