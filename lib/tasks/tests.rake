begin
  require 'rake/testtask'
rescue LoadError => e
end

if defined? Rake::TestTask
  namespace :test do
    agent_home = File.expand_path(File.join(File.dirname(__FILE__),'..','..'))

    Rake::TestTask.new(:newrelic) do |t|
      t.libs << "#{agent_home}/test"
      t.libs << "#{agent_home}/lib"
      t.pattern = "#{agent_home}/test/new_relic/**/*_test.rb"
      t.verbose = true
    end
  end
end
