# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# RUBY-839 make sure there is no STDOUT chatter
require 'open3'

class StartUpTest < MiniTest::Unit::TestCase
  def test_should_not_print_to_stdout_when_logging_available
    ruby = 'require "newrelic_rpm"; NewRelic::Agent.manual_start; NewRelic::Agent.shutdown'
    cmd = "bundle exec ruby -e '#{ruby}'"

    sin, sout, serr = Open3.popen3(cmd)
    output = sout.read + serr.read

    expected_noise = [
      "JRuby limited openssl loaded. http://jruby.org/openssl\n",
      "gem install jruby-openssl for full support.\n",
      "fatal: Not a git repository (or any of the parent directories): .git\n",
      /Exception\: java\.lang.*\n/]

    expected_noise.each {|noise| output.gsub!(noise, "")}

    assert_equal '', output.chomp
  end
end
