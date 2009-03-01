# run unit tests for the NewRelic Agent
if defined? Rake::TestTask

namespace :test do
  AGENT_HOME = File.expand_path(File.join(File.dirname(__FILE__), "..",".."))
  Rake::TestTask.new(:agent) do |t|
    t.libs << "#{AGENT_HOME}/test"
    t.libs << "#{AGENT_HOME}/lib"
    t.pattern = "#{AGENT_HOME}/test/**/tc_*.rb"
    t.verbose = true
  end
  Rake::Task['test:agent'].comment = "Run the unit tests for the Agent"

  Rake::TestTask.new(:all => ["test", "test:agent"])
  Rake::Task['test:all'].comment = "Run all tests including agent code"
end
end
