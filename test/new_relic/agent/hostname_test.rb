# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/hostname'

module NewRelic
  module Agent
    class HostnameTest < Minitest::Test
      def setup
        NewRelic::Agent::Hostname.instance_variable_set(:@hostname, nil)
        Socket.stubs(:gethostname).returns('Rivendell')
      end

      def teardown
        NewRelic::Agent::Hostname.instance_variable_set(:@hostname, nil)
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

      def test_shortens_to_prefixes_from_string
        with_dyno_name('Imladris.1', :'heroku.use_dyno_names' => true,
                                     :'heroku.dyno_name_prefixes_to_shorten' => 'Imladris') do
          assert_equal 'Imladris.*', NewRelic::Agent::Hostname.get
        end
      end

      def test_shortens_to_prefixes_from_string_allows_csv
        with_dyno_name('Imladris.1', :'heroku.use_dyno_names' => true,
                                     :'heroku.dyno_name_prefixes_to_shorten' => 'Rivendell,Imladris') do
          assert_equal 'Imladris.*', NewRelic::Agent::Hostname.get
        end
      end

      def test_shortens_to_prefixes_with_empty_string
        with_dyno_name('Imladris.1', :'heroku.use_dyno_names' => true,
                                     :'heroku.dyno_name_prefixes_to_shorten' => '') do
          assert_equal 'Imladris.1', NewRelic::Agent::Hostname.get
        end
      end

      def test_shortens_to_prefixes_with_unsupported_object
        with_dyno_name('Imladris.1', :'heroku.use_dyno_names' => true,
                                     :'heroku.dyno_name_prefixes_to_shorten' => Object.new) do
          expects_logging(:error, includes('heroku.dyno_name_prefixes_to_shorten'), instance_of(ArgumentError))
          assert_equal 'Imladris.1', NewRelic::Agent::Hostname.get
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
