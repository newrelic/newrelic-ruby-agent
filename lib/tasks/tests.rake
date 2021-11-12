begin
  require 'rake/testtask'
rescue LoadError
end

if defined? Rake::TestTask
  namespace :test do
    def look_for_seed(tasks)
      matches = tasks.map { |t| /(seed=.*?)[,\]]/.match(t) }.compact
      matches.first[1] if matches.any?
    end

    tasks = Rake.application.top_level_tasks
    ENV['TESTOPTS'] ||= ''
    ENV['TESTOPTS'] += ' -v' if tasks.any? { |t| t.include?('verbose') }
    if seed = look_for_seed(tasks)
      ENV['TESTOPTS'] += ' --' + seed
    end

    agent_home = File.expand_path(File.join(File.dirname(__FILE__), '..', '..'))

    Rake::TestTask.new(:newrelic) do |t|
      file_pattern = ENV['file']
      file_pattern = file_pattern.split(',').map { |f| "#{agent_home}/#{f}".gsub('//', '/') } if file_pattern
      file_pattern ||= "#{agent_home}/test/new_relic/**/*_test.rb"

      t.libs << "#{agent_home}/test"
      t.libs << "#{agent_home}/lib"
      t.pattern = Array(file_pattern)
      t.verbose = true
    end
  end
end
