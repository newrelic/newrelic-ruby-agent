require 'rubygems'
require "#{File.dirname(__FILE__)}/lib/new_relic/version.rb"
require 'rake/testtask'

require "#{File.dirname(__FILE__)}/lib/tasks/all.rb"

task :test => Rake::Task['test:newrelic']

task :default => :test

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
