require 'rubygems'
require 'rake/gempackagetask'
require 'lib/newrelic/version.rb'
#require 'merb-core'
#require 'merb-core/tasks/merb'

GEM_NAME = "newrelic"
GEM_VERSION = NewRelic::VERSION::STRING
AUTHOR = "Bill Kayser"
EMAIL = "bkayser@newrelic.com"
HOMEPAGE = "http://www.newrelic.com"
SUMMARY = "Performance Monitoring Agent for New Relic Ruby Performance Monitoring Service"

spec = Gem::Specification.new do |s|
  s.rubyforge_project = 'newrelic'
  s.name = GEM_NAME
  s.version = GEM_VERSION
  s.platform = Gem::Platform::RUBY
  s.has_rdoc = true
  s.extra_rdoc_files = ["README", "LICENSE", 'TODO']
  s.summary = SUMMARY
  s.description = s.summary
  s.author = AUTHOR
  s.email = EMAIL
  s.homepage = HOMEPAGE
  s.add_dependency('merb-core', '>= 0.9.9')
  s.require_path = 'lib'
  s.files = %w(LICENSE README newrelic.yml Rakefile TODO) + Dir.glob("{lib,tasks,spec}/**/*") 
  
end

Rake::GemPackageTask.new(spec) do |pkg|
  pkg.gem_spec = spec
end

desc "install the plugin as a gem"
task :install do
  Merb::RakeHelper.install(GEM_NAME, :version => GEM_VERSION)
end

desc "Uninstall the gem"
task :uninstall do
  Merb::RakeHelper.uninstall(GEM_NAME, :version => GEM_VERSION)
end

desc "Create a gemspec file"
task :gemspec do
  File.open("#{GEM_NAME}.gemspec", "w") do |file|
    file.puts spec.to_ruby
  end
end
