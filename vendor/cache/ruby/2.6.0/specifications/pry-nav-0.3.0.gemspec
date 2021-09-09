# -*- encoding: utf-8 -*-
# stub: pry-nav 0.3.0 ruby lib

Gem::Specification.new do |s|
  s.name = "pry-nav".freeze
  s.version = "0.3.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Gopal Patel".freeze]
  s.date = "2019-04-16"
  s.description = "Turn Pry into a primitive debugger. Adds 'step' and 'next' commands to control execution.".freeze
  s.email = "nixme@stillhope.com".freeze
  s.homepage = "https://github.com/nixme/pry-nav".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 1.8.7".freeze)
  s.rubygems_version = "3.0.3".freeze
  s.summary = "Simple execution navigation for Pry.".freeze

  s.installed_by_version = "3.0.3" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<pry>.freeze, [">= 0.9.10", "< 0.13.0"])
      s.add_development_dependency(%q<pry-remote>.freeze, ["~> 0.1.6"])
    else
      s.add_dependency(%q<pry>.freeze, [">= 0.9.10", "< 0.13.0"])
      s.add_dependency(%q<pry-remote>.freeze, ["~> 0.1.6"])
    end
  else
    s.add_dependency(%q<pry>.freeze, [">= 0.9.10", "< 0.13.0"])
    s.add_dependency(%q<pry-remote>.freeze, ["~> 0.1.6"])
  end
end
