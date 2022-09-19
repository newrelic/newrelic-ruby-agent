module NewRelicTest
  def run(reporter, options = {})
    reporter.reporters.each do |reporter|
      reporter.before_test(self) if defined?(reporter.before_test)
    end
    super
  end
end

Minitest::Runnable.singleton_class.send(:prepend, NewRelicTest)
