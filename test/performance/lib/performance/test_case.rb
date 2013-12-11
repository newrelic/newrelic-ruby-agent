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

    def self.skip_test(test_method_name, options={})
      skip_specifiers << [test_method_name, options]
    end

    def self.skip_specifiers
      @skip_specifiers ||= []
    end

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
      results = self.methods.map(&:to_s).select { |m| m =~ /^test_/ }
      self.class.skip_specifiers.each do |specifier|
        method_name, options = *specifier
        skipped_platforms = Array(options[:platforms])
        skipped = Platform.current.match_any?(skipped_platforms)
        results.delete(method_name.to_s) if skipped
      end
      results
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
