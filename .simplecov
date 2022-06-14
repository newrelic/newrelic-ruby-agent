SimpleCov.start do
  if RUBY_VERSION >= '2.5.0'
    enable_coverage :branch
    add_filter "/test/"
    # SimpleCov.root
    # SimpleCov.coverage_dir
  end
end
