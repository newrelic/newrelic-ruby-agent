# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

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

class MiniTest::Unit
  def puke klass, meth, e
    if fail_fast? && !e.is_a?(MiniTest::Skip)
      puke_fast klass, meth, e
    else
      super klass, meth, e
    end
  end

  def puke_fast klass, meth, e
    warn %Q(\n\nFailing fast.\n\n#{klass}:#{meth}\n\n#{e.message}\n\n#{e.backtrace.join("\n")}\n\n)
    raise Interrupt # other exceptions will be caught by MiniTest
  end

  def fail_fast?
    ENV['MT_FAIL_FAST']
  end
end
