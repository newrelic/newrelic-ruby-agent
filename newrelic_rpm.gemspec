#-*- coding: utf-8 -*-

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'new_relic/version'
require 'new_relic/latest_changes'

Gem::Specification.new do |s|
  s.name = "newrelic_rpm"
  s.version = NewRelic::VERSION::STRING
  s.required_ruby_version = '>= 1.8.7'
  s.required_rubygems_version = Gem::Requirement.new("> 1.3.1") if s.respond_to? :required_rubygems_version=
  s.authors = [ "Tim Krajcar", "Matthew Wear", "Katherine Wu", "Karl Sandwich", "Caito Scherr" ]
  s.date = Time.now.strftime('%Y-%m-%d')
  s.licenses    = ['New Relic', 'MIT', 'Ruby']
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
    "CHANGELOG",
    "LICENSE",
    "README.md",
    "CONTRIBUTING.md",
    "newrelic.yml"
  ]

  file_list = `git ls-files`.split
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
  s.add_development_dependency 'pry', '~> 0.9.12'
  s.add_development_dependency 'hometown', '~> 0.2.5'

  # Only let Guard run on newer Rubies
  if RUBY_VERSION >= "1.9.3"
    s.add_development_dependency 'guard'
    s.add_development_dependency 'guard-minitest'
    s.add_development_dependency 'rb-fsevent'
  end

  # rack-cache ~> 1.2 is specified by actionpack 3.2, but rack-cache 1.3.1 only works on Ruby 1.9.3 & newer. :(
  # https://github.com/rtomayko/rack-cache/issues/124
  if RUBY_VERSION < "1.9.3"
   s.add_development_dependency "rack-cache", "~> 1.2.0"
  end

  # version lock down for i18n that is compatible with Ruby 1.8.7
  s.add_development_dependency 'i18n', '0.6.11'

  if RUBY_PLATFORM == 'java'
    s.add_development_dependency 'activerecord-jdbcsqlite3-adapter'
    s.add_development_dependency 'jruby-openssl', '~> 0.9.10' unless JRUBY_VERSION > '1.7'
  else
    s.add_development_dependency 'sqlite3'
  end

  if defined?(RUBY_ENGINE) && RUBY_ENGINE == 'rbx'
    s.add_development_dependency 'rubysl'
    s.add_development_dependency 'racc'
  end
end
