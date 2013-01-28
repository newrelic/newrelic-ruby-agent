require 'rubygems'
require 'rake/testtask'
require "#{File.dirname(__FILE__)}/lib/new_relic/version.rb"
require "#{File.dirname(__FILE__)}/lib/tasks/all.rb"

task :default => :test

task :test => [:gemspec, 'test:newrelic']

namespace :test do
  desc "Run all tests"
  task :all => %w{newrelic multiverse}

  agent_home = File.expand_path(File.dirname(__FILE__))

  desc "Run functional test suite for newrelic"
  task :multiverse, [:suite, :mode] => [:gemspec] do |t, args|
    args.with_defaults(:suite => "", :mode => "")
    if args.mode == "run_one"
      puts `#{agent_home}/test/multiverse/script/run_one #{args.suite}`
    else
      ruby "#{agent_home}/test/multiverse/script/runner #{args.suite}"
    end
  end

  desc "Test the multiverse testing framework by executing tests in test/multiverse/test. Get meta with it."
  task 'multiverse:self', [:suite, :mode] => [:gemspec] do |t, args|
    args.with_defaults(:suite => "", :mode => "")
    puts ("Testing the multiverse testing framework...")
    test_files = FileList['test/multiverse/test/*_test.rb']
    ruby test_files.join(" ")
  end

  Rake::TestTask.new(:intentional_fail) do |t|
    t.libs << "#{agent_home}/test"
    t.libs << "#{agent_home}/lib"
    t.pattern = "#{agent_home}/test/intentional_fail.rb"
    t.verbose = true
  end

  # Note unit testing task is defined in lib/tasks/tests.rake to facilitate
  # running them in a rails application environment.

end

desc 'Generate gemspec [ build_number, stage ]'
task :gemspec, [ :build_number, :stage ] do |t, args|
  require 'erb'
  version = NewRelic::VERSION::STRING.split('.')[0..2]
  version << args.build_number.to_s if args.build_number
  version << args.stage.to_s        if args.stage

  version_string = version.join('.')
  gem_version    = Gem::VERSION
  date           = Time.now.strftime('%Y-%m-%d')
  files          = `git ls-files`.split + ['newrelic_rpm.gemspec']

  template = ERB.new(File.read('newrelic_rpm.gemspec.erb'))
  File.open('newrelic_rpm.gemspec', 'w') do |gemspec|
    gemspec.write(template.result(binding))
  end
end
