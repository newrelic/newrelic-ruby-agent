# -*- encoding: utf-8 -*-
# stub: hometown 0.2.5 ruby lib

Gem::Specification.new do |s|
  s.name = "hometown".freeze
  s.version = "0.2.5"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Jason R. Clark".freeze]
  s.date = "2014-09-04"
  s.description = "Track object creation to stamp out pesky leaks.".freeze
  s.email = ["jason@jasonrclark.com".freeze]
  s.homepage = "http://github.com/jasonrclark/hometown".freeze
  s.licenses = ["MIT".freeze]
  s.rubygems_version = "3.2.22".freeze
  s.summary = "Track object creation".freeze

  s.installed_by_version = "3.2.22" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_development_dependency(%q<bundler>.freeze, ["~> 1.6"])
    s.add_development_dependency(%q<coveralls>.freeze, ["~> 0.7"])
    s.add_development_dependency(%q<rake>.freeze, ["~> 10.2"])
    s.add_development_dependency(%q<minitest>.freeze, ["~> 5.3"])
    s.add_development_dependency(%q<pry>.freeze, ["~> 0.9"])
    s.add_development_dependency(%q<pry-nav>.freeze, ["~> 0.2"])
    s.add_development_dependency(%q<guard>.freeze, ["~> 2.6"])
    s.add_development_dependency(%q<guard-minitest>.freeze, ["~> 1.3"])
  else
    s.add_dependency(%q<bundler>.freeze, ["~> 1.6"])
    s.add_dependency(%q<coveralls>.freeze, ["~> 0.7"])
    s.add_dependency(%q<rake>.freeze, ["~> 10.2"])
    s.add_dependency(%q<minitest>.freeze, ["~> 5.3"])
    s.add_dependency(%q<pry>.freeze, ["~> 0.9"])
    s.add_dependency(%q<pry-nav>.freeze, ["~> 0.2"])
    s.add_dependency(%q<guard>.freeze, ["~> 2.6"])
    s.add_dependency(%q<guard-minitest>.freeze, ["~> 1.3"])
  end
end
