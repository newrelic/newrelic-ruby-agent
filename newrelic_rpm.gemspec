#-*- coding: utf-8 -*-

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'new_relic/version'
require 'new_relic/latest_changes'

Gem::Specification.new do |s|
  s.name = "newrelic_rpm"
  s.version = NewRelic::VERSION::STRING
  s.required_rubygems_version = Gem::Requirement.new("> 1.3.1") if s.respond_to? :required_rubygems_version=
  s.authors = [ "Jason Clark", "Sam Goldstein", "Michael Granger", "Jon Guymon", "Ben Weintraub" ]
  s.date = Time.now.strftime('%Y-%m-%d')
  s.description = <<-EOS
New Relic is a performance management system, developed by New Relic,
Inc (http://www.newrelic.com).  New Relic provides you with deep
information about the performance of your web application as it runs
in production. The New Relic Ruby Agent is dual-purposed as a either a
Gem or plugin, hosted on
http://github.com/newrelic/rpm/
EOS
  s.email = "support@newrelic.com"
  s.executables = [ "mongrel_rpm", "newrelic_cmd", "newrelic" ]
  s.extra_rdoc_files = [
    "CHANGELOG",
    "LICENSE",
    "README.md",
    "GUIDELINES_FOR_CONTRIBUTING.md",
    "newrelic.yml"
  ]

  file_list = `git ls-files`.split
  build_file_path = 'lib/new_relic/build.rb'
  file_list << build_file_path if File.exist?(build_file_path)
  s.files = file_list

  s.homepage = "http://www.github.com/newrelic/rpm"
  s.rdoc_options = ["--line-numbers", "--inline-source", "--title", "New Relic Ruby Agent"]
  s.require_paths = ["lib"]
  s.rubygems_version = Gem::VERSION
  s.summary = "New Relic Ruby Agent"
  s.post_install_message = NewRelic::LatestChanges.read

  # Only sign with our private key if you can find it
  signing_key_path = File.expand_path('~/.ssh/newrelic_rpm-private_key.pem')
  if File.exists?(signing_key_path)
    s.signing_key   = signing_key_path
    s.cert_chain    = ['gem-public_cert.pem']
  end
end
