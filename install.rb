# frozen_string_literal: true

# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

if __FILE__ == $0 || $0 =~ /script\/plugin/ || File.basename($0) == 'rake'
  $LOAD_PATH << File.expand_path(File.join(File.dirname(__FILE__), 'lib'))
  require 'new_relic/cli/command'
  begin
    NewRelic::Cli::Install.new(:quiet => true, :app_name => 'My Application').run
  rescue NewRelic::Cli::Command::CommandFailure => e
    $stderr.puts e.message
  end
end
