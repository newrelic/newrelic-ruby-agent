require 'rubygems'
require 'rake/testtask'
require "#{File.dirname(__FILE__)}/lib/new_relic/version.rb"
require "#{File.dirname(__FILE__)}/lib/tasks/all.rb"

task :default => :test

task :test => ['test:newrelic']

namespace :test do
  desc "Run all tests"
  task :all => %w{newrelic multiverse}

  begin
    require 'test_bisect'
    TestBisect::BisectTask.new do |t|
      t.test_task_name = 'test:newrelic'
    end
  rescue LoadError
  end

  agent_home = File.expand_path(File.dirname(__FILE__))

  desc "Run functional test suite for newrelic"
  task :multiverse, [:suite, :mode] => [] do |t, args|
    args.with_defaults(:suite => "", :mode => "")
    if args.mode == "run_one"
      puts `#{agent_home}/test/multiverse/script/run_one #{args.suite}`
    else
      ruby "#{agent_home}/test/multiverse/script/runner #{args.suite}"
    end
  end

  desc "Test the multiverse testing framework by executing tests in test/multiverse/test. Get meta with it."
  task 'multiverse:self', [:suite, :mode] => [] do |t, args|
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

desc 'Record build number and stage'
task :record_build, [ :build_number, :stage ] do |t, args|
  build_string = args.build_number
  build_string << ".#{args.stage}" if args.stage

  gitsha = File.exists?(".git") ? `git rev-parse HEAD` : "Unknown"
  gitsha.chomp!

  File.open("lib/new_relic/build.rb", "w") do |f|
    f.write("# GITSHA: #{gitsha}\n")
    f.write("module NewRelic; module VERSION; BUILD='#{build_string}'; end; end\n")
  end
end
