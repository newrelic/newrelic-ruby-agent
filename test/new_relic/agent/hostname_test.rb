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

      def test_get_display_host
        with_config(:'process_host.display_name' => 'Mordor') do
          assert_equal 'Mordor', NewRelic::Agent::Hostname.get_display_host
        end
      end

      def test_get_display_host_is_nil_if_missing
        assert_nil NewRelic::Agent::Hostname.get_display_host
      end

      def test_get_display_host_warns_if_too_long
        original = 'J' * 1000
        expects_logging(:warn, any_parameters)
        with_config(:'process_host.display_name' => original) do
          refute_equal original, NewRelic::Agent::Hostname.get_display_host
        end
      end

      def test_shortens_to_prefix_if_using_dyno_names_and_matches
        with_dyno_name('Imladris.1', :'heroku.use_dyno_names' => true,
                                     :'heroku.dyno_name_prefixes_to_shorten' => ['Imladris']) do
          assert_equal 'Imladris.*', NewRelic::Agent::Hostname.get
        end
      end

      def test_does_not_shorten_if_not_using_dyno_names
        with_dyno_name('Imladris', :'heroku.use_dyno_names' => false,
                                   :'heroku.dyno_name_prefixes_to_shorten' => ['Rivendell']) do
          Socket.stubs(:gethostname).returns('Rivendell.1')
          assert_equal 'Rivendell.1', NewRelic::Agent::Hostname.get
        end
      end

      def test_only_shortens_if_matches_prefix_and_dot
        with_dyno_name('ImladrisImladrisFakeout.1',
                       :'heroku.use_dyno_names' => true,
                       :'heroku.dyno_name_prefixes_to_shorten' => ['Imladris']) do
          assert_equal 'ImladrisImladrisFakeout.1', NewRelic::Agent::Hostname.get
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
