#-*- coding: utf-8 -*-
# frozen_string_literal: true

require 'fileutils'

agent_lib = File.expand_path('../../lib', __FILE__)
$LOAD_PATH.unshift(agent_lib) unless $LOAD_PATH.include?(agent_lib)

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'new_relic/version'

Gem::Specification.new do |s|

  def self.copy_files filelist
    subfolder = File.expand_path File.dirname(__FILE__)

    filelist.each do |filename|
      source_full_filename = File.expand_path(filename)
      dest_full_filename = File.join(subfolder, File.basename(filename))
      FileUtils.cp source_full_filename, dest_full_filename
    end
  end

  shared_files = [
    "../LICENSE",
    "../CONTRIBUTING.md",
  ]

  self.copy_files shared_files

  s.name = "newrelic-infinite_tracing"
  s.version = NewRelic::VERSION::STRING
  s.required_ruby_version = '>= 2.3.0'
  s.required_rubygems_version = Gem::Requirement.new("> 1.3.1") if s.respond_to? :required_rubygems_version=
  s.authors = [ "Rachel Klein", "Tanna McClure", "Michael Lang" ]
  s.date = Time.now.strftime('%Y-%m-%d')
  s.licenses = ['Apache-2.0']
  s.description = <<-EOS
The New Relic Ruby agent requires the gem newrelic_rpm, and it includes distributed
tracing that uses head-based sampling (standard distributed tracing).

If you want distributed tracing to use tail-based sampling (Infinite Tracing),
you need to add both newrelic_rpm and newrelic-infinite_tracing to your application's
Gemfile.  For more information, see: https://docs.newrelic.com/docs/understand-dependencies/distributed-tracing/get-started/introduction-distributed-tracing

New Relic is a performance management system, developed by New Relic,
Inc (http://www.newrelic.com).  New Relic provides you with deep
information about the performance of your web application as it runs
in production. The New Relic Ruby Agent is dual-purposed as a either a
Gem or plugin, hosted on https://github.com/newrelic/newrelic-ruby-agent/
EOS

  s.email = "support@newrelic.com"
  s.executables = []
  s.extra_rdoc_files = [
    "CHANGELOG.md",
    "LICENSE"
  ]

  s.metadata = {
    'bug_tracker_uri'   => 'https://github.com/newrelic/newrelic-ruby-agent/issues',
    'changelog_uri'     => 'https://github.com/newrelic/newrelic-ruby-agent/blob/main/infinite_tracing/CHANGELOG.md',
    'documentation_uri' => 'https://docs.newrelic.com/docs/agents/ruby-agent',
    'source_code_uri'   => 'https://github.com/newrelic/newrelic-ruby-agent',
    "homepage_uri"      => "https://newrelic.com/products/edge-infinite-tracing",
  }

  file_list = `git ls-files . -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/(?!agent_helper.rb)}) }
  s.files = file_list

  s.homepage = "https://github.com/newrelic/newrelic-ruby-agent/tree/main/infinite_tracing"
  s.require_paths = ["lib", "infinite_tracing"]
  s.rubygems_version = Gem::VERSION
  s.summary = "New Relic Infinite Tracing for the Ruby agent"

  s.add_dependency 'newrelic_rpm', NewRelic::VERSION::STRING
  s.add_dependency 'grpc', '~> 1.34'

  s.add_development_dependency 'rake', '12.3.3'
  s.add_development_dependency 'rb-inotify', '0.9.10'   # locked to support < Ruby 2.3 (and listen 3.0.8)
  s.add_development_dependency 'listen', '3.0.8'        # locked to support < Ruby 2.3
  s.add_development_dependency 'minitest', '~> 5.14.0'
  s.add_development_dependency 'mocha', '~> 1.9.0'
  s.add_development_dependency 'pry-nav', '~> 0.3.0'
  s.add_development_dependency 'pry-stack_explorer', '~> 0.4.9'
  s.add_development_dependency 'guard', '~> 2.16.0'
  s.add_development_dependency 'guard-minitest', '~> 2.4.0'
  s.add_development_dependency 'hometown', '~> 0.2.5'
  s.add_development_dependency 'bundler'

  s.add_development_dependency 'grpc-tools', "~> 1.14"
end
