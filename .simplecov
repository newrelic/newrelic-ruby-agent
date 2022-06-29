SimpleCov.start do
  enable_coverage :branch
  SimpleCov.root(File.join(File.dirname(__FILE__), '/lib'))
  track_files "**/*.rb"
end
