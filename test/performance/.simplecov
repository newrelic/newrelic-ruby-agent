# frozen_string_literal: true

SimpleCov.start do
  enable_coverage(:branch)
  SimpleCov.root(File.join(File.expand_path('../../..', __FILE__), 'lib'))
  SimpleCov.command_name('Performance Tests')
  SimpleCov.coverage_dir(File.join(File.expand_path('../coverage', __FILE__)))
  track_files('**/*.rb')
  add_filter('chain.rb')
  formatter(SimpleCov::Formatter::SimpleFormatter) if ENV['CI']
end
