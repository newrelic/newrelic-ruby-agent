require 'rubygems'
require "#{File.dirname(__FILE__)}/lib/new_relic/version.rb"
require 'rake/testtask'

load "#{File.dirname(__FILE__)}/lib/tasks/all.rb"

task :test => Rake::Task['test:newrelic']

begin
  require 'rcov/rcovtask'
  Rcov::RcovTask.new do |test|
    test.libs << 'test'
    test.pattern = 'test/**/test_*.rb'
    test.verbose = true
  end
rescue LoadError
  task :rcov do
    abort "RCov is not available."
  end
end

task :test => :check_dependencies

task :default => :test

begin
  require 'rdoc/task'
  RDoc::Task.new do |rdoc|
    rdoc.rdoc_dir = 'rdoc'
    rdoc.title = "New Relic Ruby Agent (v#{NewRelic::VERSION::STRING})"
    rdoc.main = "README.rdoc"
    rdoc.rdoc_files =  FileList['lib/**/*.rb'] + FileList['README*','LICENSE','newrelic.yml', 'CHANGELOG']
    rdoc.inline_source = true
  end
rescue LoadError
  task :rdoc do
    abort "rdoc is not available."
  end
end

begin
  require 'sdoc_helpers'
rescue LoadError
  puts "sdoc support not enabled. Please gem install sdoc-helpers."
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
  files          = `git ls-files`.split

  template = ERB.new(File.read('newrelic_rpm.gemspec.erb'))
  File.open('newrelic_rpm.gemspec', 'w') do |gemspec|
    gemspec.write(template.result(binding))
  end
end
