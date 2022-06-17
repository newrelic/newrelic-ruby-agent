SimpleCov.start do
  # if RUBY_VERSION >= '2.5.0'
    enable_coverage :branch
    puts "--------------- waluigi"
    SimpleCov.root(File.join(File.dirname(__FILE__), '/lib'))
    puts "&&&&&&&&&&&&&&&&&&&&&&&", SimpleCov.root
    track_files "**/*.rb"
    # end
end
