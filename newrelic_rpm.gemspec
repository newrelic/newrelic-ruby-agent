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
  s.authors = [ "Jason Clark", "Tim Krajcar", "Chris Pine", "Jonan Scheffler", "Ben Weintraub" ]
  s.date = Time.now.strftime('%Y-%m-%d')
  s.licenses    = ['New Relic', 'MIT', 'Ruby']
  s.description = <<-EOS
New Relic is a performance management system, developed by New Relic,
Inc (http://www.newrelic.com).  New Relic provides you with deep
information about the performance of your web application as it runs
in production. The New Relic Ruby Agent is dual-purposed as a either a
Gem or plugin, hosted on
http://github.com/newrelic/rpm/
EOS
  s.email = "support@newrelic.com"
  s.executables = [ "mongrel_rpm", "newrelic_cmd", "newrelic", "nrdebug" ]
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
  s.require_paths = ["lib"]
  s.rubygems_version = Gem::VERSION
  s.summary = "New Relic Ruby Agent"

  s.add_development_dependency 'rake', '10.1.0'
  s.add_development_dependency 'minitest', '~> 4.7.5'
  s.add_development_dependency 'mocha', '~> 0.13.0'

  # ActiveSupport > 3.2.9 depends on il18n ~> 0.7
  # which in turn only support Ruby 1.9.3
  # This following workaround to ensure we could test
  # Rails 3 on Ruby <= 1.9.2
  s.add_development_dependency 'i18n', '~> 0.6'
  s.add_development_dependency 'rails', '~> 3.2.13'

  s.add_development_dependency 'yard'
  s.add_development_dependency 'pry', '~> 0.9.12'
  s.add_development_dependency 'guard', '~> 1.8.3' # Guard 2.0 is Ruby 1.9 only
  s.add_development_dependency 'guard-minitest'
  s.add_development_dependency 'rb-fsevent', '~> 0.9.1'
  s.add_development_dependency 'hometown', '~> 0.2.5'
  s.add_development_dependency 'jruby-openssl' if RUBY_PLATFORM == 'java'

  if RUBY_PLATFORM == 'java'
    s.add_development_dependency 'activerecord-jdbcsqlite3-adapter'
  else
    s.add_development_dependency 'sqlite3'
  end

  if defined?(RUBY_ENGINE) && RUBY_ENGINE == 'rbx'
    s.add_development_dependency 'rubysl'
    s.add_development_dependency 'racc'
  end

  # Only sign with our private key if you can find it
  signing_key_path = File.expand_path('~/.ssh/newrelic_rpm-private_key.pem')
  if File.exists?(signing_key_path)
    s.signing_key   = signing_key_path
    s.cert_chain    = ['gem-public_cert.pem']
  end
end
