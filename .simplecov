SimpleCov.start do
  if RUBY_VERSION >= '2.5.0'
    enable_coverage :branch
    SimpleCov.root('/Users/kreopelle/dev/newrelic-ruby-agent/lib')
  end
end
