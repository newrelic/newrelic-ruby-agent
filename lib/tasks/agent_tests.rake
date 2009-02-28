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
    
    desc 'Run all unit, functional and integration tests'
    task :all do
      errors = %w(test:units test:functionals test:integration test:agent).collect do |task|
        begin
          Rake::Task[task].invoke
          nil
        rescue => e
          task
        end
      end.compact
      abort "Errors running #{errors.to_sentence}!" if errors.any?
    end
  end
end
