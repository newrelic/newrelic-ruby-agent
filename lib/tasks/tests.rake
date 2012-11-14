begin
  require 'rake/testtask'
rescue LoadError => e
end

if defined? Rake::TestTask
  task :test => 'test:newrelic'
  task :default => :test
  namespace :test do
    AGENT_HOME = File.expand_path(File.join(File.dirname(__FILE__),'..','..'))
    Rake::TestTask.new(:newrelic) do |t|
      t.libs << "#{AGENT_HOME}/test"
      t.libs << "#{AGENT_HOME}/lib"
      t.pattern = "#{AGENT_HOME}/test/**/*_test.rb"
      t.verbose = true
    end

    Rake::TestTask.new(:intentional_fail) do |t|
      t.libs << "#{AGENT_HOME}/test"
      t.libs << "#{AGENT_HOME}/lib"
      t.pattern = "#{AGENT_HOME}/test/intentional_fail.rb"
      t.verbose = true
    end
  end
end
