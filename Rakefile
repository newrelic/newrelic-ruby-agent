require 'rubygems'
require "#{File.dirname(__FILE__)}/lib/new_relic/version.rb"
require "#{File.dirname(__FILE__)}/lib/tasks/all.rb"


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
