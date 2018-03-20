#-*- coding: utf-8 -*-

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'new_relic/version'
require 'new_relic/latest_changes'

Gem::Specification.new do |s|
  s.name = "newrelic_rpm"
  s.version = NewRelic::VERSION::STRING
  s.required_ruby_version = '>= 2.0.0'
  s.required_rubygems_version = Gem::Requirement.new("> 1.3.1") if s.respond_to? :required_rubygems_version=
  s.authors = [ "Matthew Wear", "Chris Pine", "Erin Dees" ]
  s.date = Time.now.strftime('%Y-%m-%d')
  s.licenses    = ['New Relic']
  s.description = <<-EOS
New Relic is a performance management system, developed by New Relic,
Inc (http://www.newrelic.com).  New Relic provides you with deep
information about the performance of your web application as it runs
in production. The New Relic Ruby Agent is dual-purposed as a either a
Gem or plugin, hosted on
https://github.com/newrelic/rpm/
EOS
  s.email = "support@newrelic.com"
  s.executables = [ "mongrel_rpm", "newrelic_cmd", "newrelic", "nrdebug" ]
  s.extra_rdoc_files = [
    "CHANGELOG.md",
    "LICENSE",
    "README.md",
    "CONTRIBUTING.md",
    "newrelic.yml"
  ]

  file_list = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/(?!agent_helper.rb)}) }
  build_file_path = 'lib/new_relic/build.rb'
  file_list << build_file_path if File.exist?(build_file_path)
  s.files = file_list

  s.homepage = "https://github.com/newrelic/rpm"
  s.require_paths = ["lib"]
  s.rubygems_version = Gem::VERSION
  s.summary = "New Relic Ruby Agent"

  s.add_development_dependency 'rake', '10.1.0'
  s.add_development_dependency 'minitest', '~> 4.7.5'
  s.add_development_dependency 'mocha', '~> 0.13.0'
  s.add_development_dependency 'yard'
  s.add_development_dependency 'rails', '~> 3.2.13'
  s.add_development_dependency 'json', '>= 2.0.2' if RUBY_VERSION >= '2.4.0' # possible bundler issue?
  s.add_development_dependency 'pry-nav', '~> 0.2.4'
  s.add_development_dependency 'pry-stack_explorer', '~> 0.4.9'
  s.add_development_dependency 'hometown', '~> 0.2.5'

  if RUBY_PLATFORM == 'java'
    s.add_development_dependency 'activerecord-jdbcsqlite3-adapter'
  else
    s.add_development_dependency 'sqlite3'
  end
end
