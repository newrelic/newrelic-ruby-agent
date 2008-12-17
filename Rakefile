require 'rubygems'
require 'rake/gempackagetask'
require 'lib/new_relic/version.rb'

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
  s.extra_rdoc_files = ["README", "LICENSE"]
  s.summary = SUMMARY
  s.description = s.summary
  s.author = AUTHOR
  s.email = EMAIL
  s.homepage = HOMEPAGE
  s.require_path = 'lib'
  s.files = %w(install.rb LICENSE README newrelic.yml Rakefile) + Dir.glob("{lib,tasks,test,ui}/**/*") 
  
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
