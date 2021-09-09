require "bundler/gem_tasks"

require 'rake/testtask'

task :default => :test

Rake::TestTask.new do |test|
  test.verbose = true
  test.libs << "test"
  test.libs << "lib"
  test.test_files = FileList['test/**/*_test.rb']
end

if Rake::Task.task_defined?("release:source_control_push")
  puts "Found release:source_control_push task... overwriting to support push.default=nothing"

  Rake::Task['release:source_control_push'].clear
  task 'release:source_control_push' do
    `git push origin master`

    version = Bundler::GemHelper.gemspec.version
    version_tag = "v#{version}"
    `git tag -a -m \"Version #{version}\" #{version_tag}`
    `git push --tags`
  end
end
