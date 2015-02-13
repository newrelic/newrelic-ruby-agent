# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

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

class ConfigFileLoadingTest < Minitest::Test
  include MultiverseHelpers

  def setup
    # While FakeFS stubs out all the File system related libraries (i.e. File,
    # FileUtils, Dir, etc.)  It doesn't handle the Logger library that is used
    # to create the agent log file.  Therefore we check for the presence of the
    # log directory in the FakeFS, then error when we try to open the file in
    # the Real FS.  Set the log file to /dev/null to work around this issue.
    # It's incidental to the functionality being tested.
    #
    # '/dev/null' can be changed to 'stdout' if more debugging output is needed
    # in these tests.
    ENV['NEW_RELIC_LOG'] = '/dev/null'

    # Figure out where multiverse is in the real file system.
    @cwd = Dir.pwd

    # require the agent before we're in FakeFS so require doesn't hit the fake
    require 'newrelic_rpm'

    # Use a fake file system so we don't damage the real one.
    FakeFS.activate!
    FakeFS::FileSystem.clear

    FileUtils.mkdir_p(@cwd)
  end

  def teardown
    ENV['NEW_RELIC_LOG'] = nil
    FakeFS.deactivate!
  end

  def setup_config(path, manual_config_options = {}, config_file_content=nil)
    teardown_agent

    FileUtils.mkdir_p(File.dirname(path))
    Dir.chdir @cwd
    File.open(path, 'w') do |f|
      if config_file_content
        f.write(config_file_content)
      else
        f.print <<-YAML
development:
  foo: "success!!"
test:
  foo: "success!!"
bazbangbarn:
  i_am: "bazbangbarn"
        YAML
      end
    end

    setup_agent(manual_config_options)
  end

  def assert_config_read_from(path, manual_config_options={})
    setup_config(path, manual_config_options)
    assert NewRelic::Agent.config[:foo] == "success!!", "Failed to read yaml config from #{path.inspect[0..100]}\n\n#{NewRelic::Agent.config.inspect[0..100]}"
  end

  def assert_config_not_read_from(path)
    setup_config(path)
    assert NewRelic::Agent.config[:foo] != "success!!", "Read yaml config from #{path.inspect}\n\n#{NewRelic::Agent.config.inspect}"
  end

  def test_config_loads_from_config_newrelic_yml
    assert_config_read_from(File.join(@cwd, "config/newrelic.yml"))
  end

  def test_config_loads_from_newrelic_yml
    assert_config_read_from(File.join(@cwd, "newrelic.yml"))
  end

  def test_config_loads_from_home_newrelic_yml
    assert_config_read_from(ENV['HOME'] + "/newrelic.yml")
  end

  def test_config_loads_from_home_dot_newrelic_newrelic_yml
    assert_config_read_from(ENV['HOME'] + "/.newrelic/newrelic.yml")
  end

  def test_config_loads_from_config_path_option_to_manual_start
    path = File.join(@cwd, 'otherplace', 'newrelic.yml')
    assert_config_read_from(path, :config_path => path)
  end

  def test_warning_logged_when_no_config_file
    teardown_agent
    setup_agent

    log = with_array_logger { NewRelic::Agent.manual_start }

    assert_log_contains(log, /WARN.*No configuration file found/)
    assert_log_contains(log, /WARN.*Looked in these locations.*based on defaults/)
  end

  def test_warning_logged_when_no_config_file_manual_config
    teardown_agent
    setup_agent

    log = with_array_logger do
      NewRelic::Agent.manual_start(:config_path => 'otherplace/newrelic.yml')
    end

    assert_log_contains(log, /WARN.*No configuration file found/)
    assert_log_contains(log, /WARN.*Looked in these locations.*based on API call.*otherplace\/newrelic\.yml/)
  end

  def test_warning_logged_when_no_config_file_environment_variable
    ENV['NRCONFIG'] = 'otherplace/newrelic.yml'
    teardown_agent
    setup_agent

    log = with_array_logger { NewRelic::Agent.manual_start }

    assert_log_contains(log, /WARN.*No configuration file found/)
    assert_log_contains(log, /WARN.*Looked in these locations.*based on environment variable.*otherplace\/newrelic\.yml/)
  ensure
    ENV['NRCONFIG'] = nil
  end

  def test_warning_logged_when_config_file_yaml_parsing_error
    path = File.join(@cwd, 'config', 'newrelic.yml')
    setup_config(path, {}, '<< bogus junk')
    setup_agent

    log = with_array_logger { NewRelic::Agent.manual_start }

    assert_log_contains(log, /ERROR.*Failed to read or parse configuration file at config\/newrelic\.yml/)
  end

  def test_warning_logged_when_config_file_erb_error
    path = File.join(@cwd, 'config', 'newrelic.yml')
    setup_config(path, {}, "\n\n\n<%= this is not ruby %>") # the error is on line 4
    setup_agent

    log = with_array_logger { NewRelic::Agent.manual_start }

    assert_log_contains(log, /ERROR.*Failed ERB processing/)
    assert_log_contains(log, /\(erb\):4/)
  end

  def test_exclude_commented_out_erb_lines
    config_contents = <<-YAML
development:
  foo: "success!!"
test:
  foo: "success!!"
boom:
  # <%= this is not ruby %>
        YAML

    path = File.join(@cwd, 'config', 'newrelic.yml')
    setup_config(path, {}, config_contents)
    setup_agent

    log = with_array_logger { NewRelic::Agent.manual_start }

    assert_equal "success!!", NewRelic::Agent.config[:foo]

    refute_log_contains(log, /ERROR.*Failed ERB processing/)
    refute_log_contains(log, /\(erb\)/)
  end

  def test_config_loads_from_env_NRCONFIG
    ENV["NRCONFIG"] = "/tmp/foo/bar.yml"
    assert_config_read_from("/tmp/foo/bar.yml")
  ensure
    ENV["NRCONFIG"] = nil
  end

  def test_config_isnt_loaded_from_somewhere_crazy
    assert_config_not_read_from(File.join(@cwd, "somewhere/crazy/newrelic.yml"))
  end

  def test_config_will_load_settings_for_environment_passed_manual_start
    path = File.join(@cwd, "config/newrelic.yml")

    # pass an env key to NewRelic::Agent.manual_start which should cause it to
    # load that section of newrelic.yml
    setup_config(path, {:env => 'bazbangbarn'} )
    assert_equal 'bazbangbarn', NewRelic::Agent.config[:i_am], "Agent.config did not load bazbangbarn config as requested"
  end

  def assert_log_contains(log, message)
    lines = log.array
    failure_message = "Did not find '#{message}' in log. Log contained:\n#{lines.join('')}"
    assert (lines.any? { |line| line.match(message) }), failure_message
  end

  def refute_log_contains(log, message)
    lines = log.array
    failure_message = "Found unexpected '#{message}' in log. Log contained:\n#{lines.join('')}"
    refute (lines.any? { |line| line.match(message) }), failure_message
  end
end
