# We don't want to define any constants if the gem extension isn't loaded, so not requiring the version file.

Gem::Specification.new do |spec|
  spec.name          = "debug_inspector"
  spec.version       = "1.1.0"
  spec.authors       = ["John Mair (banisterfiend)"]
  spec.email         = ["jrmair@gmail.com"]

  spec.summary       = %q{A Ruby wrapper for the MRI 2.0 debug_inspector API}
  spec.description   = <<-TXT
Adds methods to RubyVM::DebugInspector to allow for inspection of backtrace frames.

The debug_inspector C extension and API were designed and built by Koichi Sasada, this project is just a gemification of his work.

This library makes use of the debug inspector API which was added to MRI 2.0.0.
Only works on MRI 2 and 3. Requiring it on unsupported Rubies will result in a no-op.

Recommended for use only in debugging situations. Do not use this in production apps.
TXT
  spec.homepage      = "https://github.com/banister/debug_inspector"
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.0")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/banister/debug_inspector"
  spec.metadata["changelog_uri"] = "https://github.com/banister/debug_inspector/releases"

  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|bin)/}) }
  end

  spec.require_paths = ["lib"]

  if RUBY_ENGINE == "ruby"
    spec.extensions = ["ext/debug_inspector/extconf.rb"]
  end
end
