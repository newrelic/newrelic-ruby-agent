# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/hostname'

module NewRelic
  module Agent
    class HostnameTest < Minitest::Test
      def setup
        Socket.stubs(:gethostname).returns('Rivendell')
      end

      def test_get_returns_socket_hostname
        assert_equal 'Rivendell', NewRelic::Agent::Hostname.get
      end

      def test_get_uses_dyno_name_if_dyno_env_set_and_dyno_names_enabled
        with_dyno_name('Imladris', :'heroku.use_dyno_names' => true) do
          assert_equal 'Imladris', NewRelic::Agent::Hostname.get
        end
      end

      def test_get_uses_socket_gethostname_if_dyno_env_set_and_dyno_names_disabled
        with_dyno_name('Imladris', :'heroku.use_dyno_names' => false) do
          assert_equal 'Rivendell', NewRelic::Agent::Hostname.get
        end
      end

      def with_dyno_name(dyno_name, config_options)
        with_config(config_options) do
          ENV['DYNO'] = dyno_name
          yield
        end
      ensure
        ENV.delete('DYNO')
      end
    end
  end
end
