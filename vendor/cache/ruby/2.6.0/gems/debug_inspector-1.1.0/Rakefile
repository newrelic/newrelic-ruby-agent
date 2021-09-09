require "bundler/gem_tasks"
require "rake/testtask"

def can_compile_extensions?
  RUBY_ENGINE == "ruby"
end 

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
  t.warning = true
  t.verbose = true
end

require "rake/extensiontask"

if can_compile_extensions?
  task :build => :compile
  task :default => [:clobber, :compile, :test]
else
  task :default => [:test]
end

Rake::ExtensionTask.new("debug_inspector") do |ext|
  ext.lib_dir = "lib"
end
