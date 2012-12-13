# Test the logic for loading the newrelic.yml config file.
#
# We will look at (in this priority):
# 1. ENV['NRCONFIG'] (if set)
# 2. ./config/newrelic.yml
# 3. ./newrelic.yml
# 4. ~/.newrelic/newrelic.yml
# 5. ~/newrelic.yml
#
# If this fails the agent will attempt to dial Lew Cirne's cell phone and ask
# that he verbally describe how it should be configured.
class ConfigFileLoadingTest < Test::Unit::TestCase

  def setup
    @cwd = Dir.pwd
    # Use a fake file system so we don't damage the real one.
    FakeFS.activate!
    # require the agent after we're in FakeFS
    require 'newrelic_rpm'
    FakeFS::FileSystem.clear
  end

  def teardown
    FakeFS.deactivate!
  end

  def setup_config(path)
    NewRelic::Agent.shutdown

    # create a fresh Control each test case
    # FIXME: This feels dirty but's it's necessary since Agent.shutdown doesn't
    # clear the Control singleton.
    NewRelic::Control.instance_variable_set(:@instance,nil)

    FileUtils.mkdir_p(File.dirname(path))
    FileUtils.mkdir_p(@cwd)
    Dir.chdir @cwd
    File.open(path, 'w') do |f|
      f.print <<-YAML
development:
  foo: "success!!"
test:
  foo: "success!!"
      YAML
    end
    NewRelic::Agent.reset_config
    NewRelic::Agent.manual_start
  end

  def assert_config_read_from(path)
    setup_config(path)
    assert NewRelic::Agent.config[:foo] == "success!!", "Failed to read yaml config from #{path.inspect}\n\n#{NewRelic::Agent.config.inspect}"
  end

  def assert_config_not_read_from(path)
    setup_config(path)
    assert NewRelic::Agent.config[:foo] != "success!!", "Read yaml config from #{path.inspect}\n\n#{NewRelic::Agent.config.inspect}"
  end

  def test_config_loads_from_config_newrelic_yml
    assert_config_read_from(File.dirname(__FILE__) + "/config/newrelic.yml")
  end

  def test_config_loads_from_newrelic_yml
    assert_config_read_from(File.dirname(__FILE__) + "/newrelic.yml")
  end

  def test_config_loads_from_home_newrelic_yml
    assert_config_read_from(ENV['HOME'] + "/newrelic.yml")
  end

  def test_config_loads_from_home_dot_newrelic_newrelic_yml
    assert_config_read_from(ENV['HOME'] + "/.newrelic/newrelic.yml")
  end

  def test_config_loads_from_env_NRCONFIG
    ENV["NRCONFIG"] = "/tmp/foo/bar.yml"
    assert_config_read_from("/tmp/foo/bar.yml")
  ensure
    ENV["NRCONFIG"] = nil
  end

  def test_config_isnt_loaded_from_somewhere_crazy
    assert_config_not_read_from(File.dirname(__FILE__) + "/somewhere/crazy/newrelic.yml")
  end
end
