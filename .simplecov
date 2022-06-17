SimpleCov.start do
  if RUBY_VERSION >= '2.5.0'
    enable_coverage :branch
    SimpleCov.root(File.join(File.dirname(__FILE__), '/lib'))
    track_files "**/*.rb"
  end
end
