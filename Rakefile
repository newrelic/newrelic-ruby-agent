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
  task :multiverse, [:suite, :param1, :param2, :param3, :param4] => [] do |t, args|
    require File.expand_path(File.join(File.dirname(__FILE__), 'test', 'multiverse', 'lib', 'multiverse', 'environment'))
    opts = Multiverse::Runner.parse_args(args)
    if opts.key?(:run_one)
      Multiverse::Runner.run_one(args.suite, opts)
    else
      Multiverse::Runner.run(args.suite, opts)
    end
  end

  desc "Test the multiverse testing framework by executing tests in test/multiverse/test. Get meta with it."
  task 'multiverse:self', [:suite, :mode] => [] do |t, args|
    args.with_defaults(:suite => "", :mode => "")
    puts ("Testing the multiverse testing framework...")
    test_files = FileList['test/multiverse/test/*_test.rb']
    ruby test_files.join(" ")
  end

  desc "Run agent performance tests"
  task :performance, [:suite, :name] => [] do |t, args|
    require File.expand_path(File.join(File.dirname(__FILE__), 'test', 'performance', 'lib', 'performance'))
    options = {}
    options[:suite] = args[:suite] if args[:suite]
    options[:name]  = args[:name]  if args[:name]
    Performance::Runner.new(options).run_and_report
  end

  desc "Run agent within existing mini environments"
  task :env, [:env1, :env2, :env3, :env4, :env5, :env6] => [] do |t, args|
    require File.expand_path(File.join(File.dirname(__FILE__), 'test', 'environments', 'lib', 'environments', 'runner'))
    Environments::Runner.new(args.map{|_,v| v}).run_and_report
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
