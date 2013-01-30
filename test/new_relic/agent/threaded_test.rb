class ThreadedTest < Test::Unit::TestCase
  def setup
    @original_thread_class = NewRelic::Agent::AgentThread
    swap_thread_class(FakeThread)
  end

  def teardown
    swap_thread_class(@original_thread_class)
    @original_thread_class = nil

    FakeThread.list.clear
  end

  def default_test
    # no-op to keep quiet....
  end

  private

  def swap_thread_class(klass)
    NewRelic::Agent.send(:remove_const, "AgentThread") if NewRelic::Agent.const_defined?("AgentThread")
    NewRelic::Agent.const_set("AgentThread", klass)
  end
end

class FakeThread
  @@list = []

  def initialize(locals={}, &block)
    @locals = locals
    yield if block_given?
  end

  def self.current
    {}
  end

  def self.list
    @@list
  end

  def self.bucket_thread(thread, _)
    thread[:bucket] 
  end

  def self.scrub_backtrace(thread, _)
    thread[:scrubbed_backtrace] || thread.backtrace
  end

  def key?(key)
    @locals.key?(key)
  end

  def [](key)
    @locals[key]
  end

  def backtrace
    @locals[:backtrace] || []
  end

  def join
  end
end

