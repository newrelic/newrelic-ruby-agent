require 'rubygems'
require 'rake/gempackagetask'
require 'lib/new_relic/version.rb'
require 'echoe'

GEM_NAME = "newrelic_rpm"
GEM_VERSION = NewRelic::VERSION::STRING
AUTHOR = "Bill Kayser"
EMAIL = "bkayser@newrelic.com"
HOMEPAGE = "http://www.newrelic.com"
SUMMARY = "New Relic Ruby Performance Monitoring Agent"

Echoe.new(GEM_NAME) do |p|
  p.author = AUTHOR
  p.summary = SUMMARY
  p.url = HOMEPAGE
  p.email = EMAIL
  p.project = 'newrelic'
  p.need_tar_gz = false
  p.need_gem = true
end

desc "Create a gemspec file"
task :gemspec do
  File.open("#{GEM_NAME}.gemspec", "w") do |file|
    file.puts spec.to_ruby
  end
end
