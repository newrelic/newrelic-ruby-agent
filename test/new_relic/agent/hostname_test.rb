# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/hostname'

module NewRelic
  module Agent
    class HostnameTest < Minitest::Test
      def test_get_returns_socket_hostname
        Socket.stubs(:gethostname).returns('Rivendell')
        assert_equal 'Rivendell', NewRelic::Agent::Hostname.get
      end

      def test_get_uses_dyno_name_if_dyno_env_set_and_dyno_names_enabled
        with_config(:use_heroku_dyno_names => true) do
          Socket.stubs(:gethostname).returns('Rivendell')
          ENV['DYNO'] = 'Imladris'

          expected = 'Imladris'
          assert_equal expected, NewRelic::Agent::Hostname.get
        end
      ensure
        ENV.delete('DYNO')
      end

      def test_get_uses_socket_gethostname_if_dyno_env_set_and_dyno_names_disabled
        with_config(:use_heroku_dyno_names => false) do
          Socket.stubs(:gethostname).returns('Rivendell')
          ENV['DYNO'] = 'Imladris'

          expected = 'Rivendell'
          assert_equal expected, NewRelic::Agent::Hostname.get
        end
      ensure
        ENV.delete('DYNO')
      end
    end
  end
end
