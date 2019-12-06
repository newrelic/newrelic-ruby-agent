#!/usr/bin/env ruby

# Some Ruby and RubyGems versions are incompatible:
#
# * RubyGems 3.x won't install on Ruby 2.2 or older
# * RubyGems 2.x fails our no-warnings check on Ruby 2.6 or later

# Note the set -ev at the top. The -e flag causes the script to exit as soon as
# one command returns a non-zero exit code. This can be handy if you want
# whatever script you have to exit early. It also helps in complex installation
# scripts where one failed command wouldn’t otherwise cause the installation to
# fail.

if RUBY_VERSION.to_f < 2.7 
  if Gem::VERSION.to_f < 3.0
    puts "Ruby < 2.7, upgrading RubyGems from #{Gem::VERSION}"

    puts `gem update --system --force || (gem i rubygems-update -v '<3' && update_rubygems)`
    puts `rvm @global do gem uninstall bundler --all --executables || true`
    puts `gem uninstall bundler --all --executables || true`
    puts `gem install bundler -v=1.17.3 --force`

  else
    puts "Ruby < 2.7, but RubyGems already at #{Gem::VERSION}"
  end
else
  puts "Ruby >= 2.7, keeping RubyGems at #{Gem::VERSION}"
end