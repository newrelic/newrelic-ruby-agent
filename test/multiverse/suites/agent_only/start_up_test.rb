# RUBY-839 make sure there is no STDOUT chatter
require 'open3'

class StartUpTest < Test::Unit::TestCase
  def test_should_not_print_to_stdout_when_logging_available
    ruby = 'require "newrelic_rpm"; NewRelic::Agent.manual_start; NewRelic::Agent.shutdown'
    cmd = "bundle exec ruby -e '#{ruby}'"

    sin, sout, serr = Open3.popen3(cmd)

    jruby_noise = "JRuby limited openssl loaded. http://jruby.org/openssl\ngem install jruby-openssl for full support.\n"
    assert_equal '', (sout.read + serr.read).sub(jruby_noise, '')
  end
end
