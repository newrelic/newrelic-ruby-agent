# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module Performance
  class TestCase
    @subclasses = []

    def self.inherited(cls)
      @subclasses << cls
    end

    def self.subclasses
      @subclasses
    end

    attr_accessor :iterations

    def initialize
      @callbacks = {}
      @iterations = 10000
      on(:before_each, &method(:setup))
      on(:after_each,  &method(:teardown))
    end

    def setup; end
    def teardown; end

    def on(event, &action)
      @callbacks[event] ||= []
      @callbacks[event] << action
    end

    def fire(event, *args)
      if @callbacks[event]
        @callbacks[event].each { |cb| cb.arity > 0 ? cb.call(*args) : cb.call }
      end
    end

    def runnable_test_methods
      self.methods.map { |m| m.to_s }.select { |m| m =~ /^test_/ }
    end

    def with_callbacks(name)
      fire(:before_each, self, name)
      result = yield
      fire(:after_each, self, name, result)
    end

    def run(name)
      result = Result.new(self.class, name)
      begin
        with_callbacks(name) do
          if self.method(name).arity == 0
            result.timer.measure do
              self.send(name)
            end
          else
            self.send(name, result.timer)
          end
          result
        end
      rescue StandardError, LoadError => e
        result.exception = e
      end
      result
    end
  end
end
