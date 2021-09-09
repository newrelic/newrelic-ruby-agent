def fake_makefile
  File.open("Makefile", "w") { |f|
    f.puts '.PHONY: install'
    f.puts 'install:'
    f.puts "\t" + '@echo "This Ruby not supported by/does not require debug_inspector."'
  }
end

def mri_2_or_3?
  defined?(RUBY_ENGINE) && RUBY_ENGINE == "ruby" &&
    RUBY_VERSION =~ /^[23]/
end

if mri_2_or_3?
  require 'mkmf'
  create_makefile('debug_inspector')
else
  fake_makefile
end
