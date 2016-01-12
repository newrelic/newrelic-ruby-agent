begin
  require 'rake/testtask'
rescue LoadError => e
end

if defined? Rake::TestTask
  namespace :test do
    def look_for_seed(tasks)
      matches = tasks.map { |t| /(seed=.*?)[,\]]/.match(t) }.compact
      if matches.any?
        matches.first[1]
      else
        nil
      end
    end

    tasks = Rake.application.top_level_tasks
    ENV["TESTOPTS"] ||= ""
    if tasks.any? { |t| t.include?("verbose")}
      ENV["TESTOPTS"] += " -v"
    end
    if seed = look_for_seed(tasks)
      ENV["TESTOPTS"] += " --" + seed
    end

    agent_home = File.expand_path(File.join(File.dirname(__FILE__),'..','..'))

    Rake::TestTask.new(:newrelic) do |t|
      t.libs << "#{agent_home}/test"
      t.libs << "#{agent_home}/lib"
      t.pattern = "#{agent_home}/test/new_relic/**/*_test.rb"
      t.verbose = true
    end

  end
end
