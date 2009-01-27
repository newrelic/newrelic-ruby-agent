require 'rubygems'
require 'rake/gempackagetask'
require 'lib/new_relic/version.rb'

GEM_NAME = "newrelic_rpm"
GEM_VERSION = NewRelic::VERSION::STRING
AUTHOR = "Bill Kayser"
EMAIL = "bkayser@newrelic.com"
HOMEPAGE = "http://www.newrelic.com"
SUMMARY = "New Relic Ruby Performance Monitoring Agent"

spec = Gem::Specification.new do |s|
  s.rubyforge_project = 'newrelic'
  s.name = GEM_NAME
  s.version = GEM_VERSION
  s.platform = Gem::Platform::RUBY
  s.has_rdoc = true
  s.extra_rdoc_files = ["README", "LICENSE"]
  s.summary = SUMMARY
  s.description = s.summary
  s.author = AUTHOR
  s.email = EMAIL
  s.homepage = HOMEPAGE
  s.require_path = 'lib'
  s.files = %w(install.rb LICENSE README newrelic.yml Rakefile) + Dir.glob("{lib,bin,recipes,test,ui}/**/*") 
  s.bindir = "bin" # Use these for applications.
  s.executables = ["newrelic_cmd"]
  s.default_executable = "newrelic_cmd"
end

Rake::GemPackageTask.new(spec) do |pkg|
  pkg.gem_spec = spec
end

desc "Create a gemspec file"
task :gemspec do
  File.open("#{GEM_NAME}.gemspec", "w") do |file|
    file.puts spec.to_ruby
  end
end
