# run unit tests for the NewRelic Agent
begin
  require 'rake/test_task'
rescue LoadError => e
end

if defined? Rake::TestTask
  namespace :test do
    AGENT_HOME = File.expand_path(File.join(File.dirname(__FILE__), "..",".."))
    Rake::TestTask.new(:newrelic) do |t|
      t.libs << "#{AGENT_HOME}/test"
      t.libs << "#{AGENT_HOME}/lib"
      t.test_files = FileList["#{AGENT_HOME}/test/**/*_test.rb"]
      t.verbose = true

      # Set the test loader to use the Ruby provided test loading script.
      # In ruby 1.9 the default Rake provided runner seems to exit with a 0
      # status code, even when tests fail.
      t.loader = :testrb if RUBY_VERSION >= '1.9'
    end
    Rake::Task['test:newrelic'].comment = "Run the unit tests for the Agent"
    task 'test:newrelic' => :environment
  end
end
