require 'rubygems'
require 'rake'
require "#{File.dirname(__FILE__)}/lib/new_relic/version.rb"
require 'rake/testtask'

GEM_NAME = "newrelic_rpm"
GEM_VERSION = NewRelic::VERSION::STRING
AUTHORS = "Bill Kayser", "Jon Guymon", "Justin George", "Darin Swanson"
EMAIL = "support@newrelic.com"
HOMEPAGE = "http://www.github.com/newrelic/rpm"
SUMMARY = "New Relic Ruby Agent"
INSTALLATION_NOTES = "InstallationNotes.md"
RDOC_FILES = FileList['README*','LICENSE','newrelic.yml', 'CHANGELOG']

DESCRIPTION = <<-EOF
New Relic is a performance management system, developed by New Relic,
Inc (http://www.newrelic.com).  New Relic provides you with deep
information about the performance of your web application as it runs
in production. The New Relic Ruby Agent is dual-purposed as a either a
Gem or plugin, hosted on
http://github.com/newrelic/rpm/
EOF

INSTALLATION_POSTSCRIPT =  <<-EOF

Please see http://github.com/newrelic/rpm/blob/master/CHANGELOG
for a complete description of the features and enhancements available
in version #{GEM_VERSION.split('.')[0..1].join('.')} of the Ruby Agent.
  
EOF

# See http://www.rubygems.org/read/chapter/20
  
begin
  require 'jeweler'
  Jeweler::Tasks.new do |gem|
    gem.name = GEM_NAME
    gem.description = DESCRIPTION
    gem.summary = SUMMARY
    gem.email = EMAIL
    gem.homepage = HOMEPAGE
    gem.authors = AUTHORS
    gem.version = GEM_VERSION
    gem.files = FileList['**/*']
    gem.test_files = [] # You can't really run the tests unless the gem is installed.
    gem.rdoc_options <<
      "--line-numbers" <<
      "--inline-source" <<
      "--title" << SUMMARY
      "-m" << "README.rdoc"
    gem.files.reject! { |fn| fn =~ /Rakefile|init.rb|#{INSTALLATION_NOTES}|pkg\// }
    gem.add_development_dependency "jeweler"
    gem.add_development_dependency "mocha"
    gem.add_development_dependency "shoulda"
    gem.extra_rdoc_files = RDOC_FILES
    if File.exists?(INSTALLATION_NOTES)
      gem.post_install_message = File.read(INSTALLATION_NOTES) + INSTALLATION_POSTSCRIPT
    else
      gem.post_install_message = INSTALLATION_POSTSCRIPT
    end
  end
  Jeweler::GemcutterTasks.new
rescue LoadError
  puts "Jeweler (or a dependency) not available. Install it with: gem install jeweler"
end


load "#{File.dirname(__FILE__)}/lib/tasks/all.rb"

task :manifest do
  puts "Manifest task is no longer used since switching to jeweler."
end

task :test => Rake::Task['test:newrelic']

begin
  require 'rcov/rcovtask'
  Rcov::RcovTask.new do |test|
    test.libs << 'test'
    test.pattern = 'test/**/test_*.rb'
    test.verbose = true
  end
rescue LoadError
  task :rcov do
    abort "RCov is not available. In order to run rcov, you must: sudo gem install spicycode-rcov"
  end
end

task :test => :check_dependencies

task :default => :test

require 'rake/rdoctask'
Rake::RDocTask.new do |rdoc|
  rdoc.rdoc_dir = 'rdoc'
  rdoc.title = "#{SUMMARY} (v#{GEM_VERSION})"
  rdoc.main = "README.rdoc"
  rdoc.rdoc_files =  FileList['lib/**/*.rb'] + RDOC_FILES
  rdoc.inline_source = true
end

begin
  require 'sdoc_helpers'
rescue LoadError
  puts "sdoc support not enabled. Please gem install sdoc-helpers."
end
