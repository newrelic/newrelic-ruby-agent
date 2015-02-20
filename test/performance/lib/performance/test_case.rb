# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module Performance
  class TestCase
    DEFAULT_WARMUP_DURATION = 2
    DEFAULT_DURATION        = 5
    BATCH_TIME              = 0.1

    @subclasses = []

    def self.inherited(cls)
      @subclasses << cls
    end

    def self.subclasses
      @subclasses
    end

    attr_accessor :target_iterations, :target_duration

    def initialize
      @callbacks = {}
      @target_iterations = nil
      @target_duration   = DEFAULT_DURATION
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

    def with_callbacks(name, warmup=false)
      fire(:before_each, self, name) unless warmup
      yield
      fire(:after_each, self, name, @result) unless warmup
    end

    # This is used to get a rough approximation of the amount of time required
    # to call action once. We do this so that we will be able to run the actual
    # timing loop in chunks of iterations, rather than calling Time.now in
    # between every iteration.
    def estimate_time_per_iteration(action, duration)
      start_time = Time.now
      deadline = start_time + duration
      
      iterations = 0
      while Time.now < deadline
        action.call
        iterations += 1
      end
      
      (Time.now - start_time) / iterations
    end

    def estimate_iterations_per_unit_time(time_per_iteration, desired_duration)
      (desired_duration / time_per_iteration).ceil
    end

    def batch_size_in_iterations(blk)
      approx_time_per_iteration = nil
      approx_time_per_iteration = estimate_time_per_iteration(blk, DEFAULT_WARMUP_DURATION)
      estimate_iterations_per_unit_time(approx_time_per_iteration, BATCH_TIME)
    end

    def run_block_in_batches(blk, duration, batch_size)
      deadline = Time.now + duration
      total_iterations = 0
      while Time.now < deadline
        batch_iterations = 0
        while batch_iterations < batch_size
          blk.call
          batch_iterations += 1
        end
        total_iterations += batch_iterations
      end
      total_iterations
    end

    def run_block_n_times(blk, n)
      iterations = 0
      while iterations < n
        blk.call
        iterations += 1
      end
      iterations
    end

    def measure(&blk)
      total_iterations = 0
      start_time       = nil
      elapsed          = nil

      batch_size = batch_size_in_iterations(blk) unless target_iterations

      with_callbacks(@result.test_name, false) do
        start_time = Time.now
        if target_iterations
          total_iterations = run_block_n_times(blk, target_iterations)
        else
          total_iterations = run_block_in_batches(blk, target_duration, batch_size)
        end
        elapsed = Time.now - start_time
      end

      @result.iterations            = total_iterations
      @result.timer.start_timestamp = start_time
      @result.timer.elapsed         = elapsed
    end

    def run(name)
      @result = Result.new(self.class, name)
      begin
        setup
        self.send(name)
        teardown
      rescue StandardError, LoadError => e
        @result.exception = e
      end
      @result
    end
  end
end
