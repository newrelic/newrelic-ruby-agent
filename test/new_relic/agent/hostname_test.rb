# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../test_helper'
require 'new_relic/agent/hostname'

module NewRelic
  module Agent
    class HostnameTest < Minitest::Test
      def setup
        NewRelic::Agent::Hostname.instance_variable_set(:@hostname, nil)
        Socket.stubs(:gethostname).returns((+'Rivendell'))
      end

      def teardown
        NewRelic::Agent::Hostname.instance_variable_set(:@hostname, nil)
      end

      def test_get_returns_socket_hostname
        assert_equal 'Rivendell', NewRelic::Agent::Hostname.get
      end

      def test_get_returns_socket_hostname_converted_to_utf8
        computer = +'Elronds’s-Computer'
        Socket.stubs(:gethostname).returns(computer.force_encoding(Encoding::ASCII_8BIT))

        assert_equal 'Elronds’s-Computer', NewRelic::Agent::Hostname.get
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
        with_dyno_name('Imladris.1', :'heroku.use_dyno_names' => true, :'heroku.dyno_name_prefixes_to_shorten' => ['Imladris']) do
          assert_equal 'Imladris.*', NewRelic::Agent::Hostname.get
        end
      end

      def test_does_not_shorten_if_not_using_dyno_names
        with_dyno_name('Imladris', :'heroku.use_dyno_names' => false, :'heroku.dyno_name_prefixes_to_shorten' => ['Rivendell']) do
          Socket.stubs(:gethostname).returns((+'Rivendell.1'))

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
        with_dyno_name('Imladris.1', :'heroku.use_dyno_names' => true, :'heroku.dyno_name_prefixes_to_shorten' => 'Imladris') do
          assert_equal 'Imladris.*', NewRelic::Agent::Hostname.get
        end
      end

      def test_shortens_to_prefixes_from_string_allows_csv
        with_dyno_name('Imladris.1', :'heroku.use_dyno_names' => true, :'heroku.dyno_name_prefixes_to_shorten' => 'Rivendell,Imladris') do
          assert_equal 'Imladris.*', NewRelic::Agent::Hostname.get
        end
      end

      def test_shortens_to_prefixes_with_empty_string
        with_dyno_name('Imladris.1', :'heroku.use_dyno_names' => true, :'heroku.dyno_name_prefixes_to_shorten' => '') do
          assert_equal 'Imladris.1', NewRelic::Agent::Hostname.get
        end
      end

      def test_gcp_cloud_run_reports_instance_id_as_host
        NewRelic::Agent::Hostname.stubs(:gcp_instance_id).returns('1234567890')

        with_cloud_run_env('gcr-test.1', :'utilization.gcp_cloud_run.use_instance_as_host' => true) do
          assert_equal '1234567890', NewRelic::Agent::Hostname.get
        end
      end

      def test_gcp_cloud_run_prepends_revision_when_configured
        NewRelic::Agent::Hostname.stubs(:gcp_instance_id).returns('1234567890')

        with_cloud_run_env('gcr-test.1',
          :'utilization.gcp_cloud_run.use_instance_as_host' => true,
          :'utilization.gcp_cloud_run.include_revision_in_host' => true) do
          assert_equal 'gcr-test.1-1234567890', NewRelic::Agent::Hostname.get
        end
      end

      def test_gcp_cloud_run_uses_socket_hostname_when_use_instance_as_host_disabled
        NewRelic::Agent::Hostname.stubs(:gcp_instance_id).returns('1234567890')

        with_cloud_run_env('gcr-test.1', :'utilization.gcp_cloud_run.use_instance_as_host' => false) do
          assert_equal 'Rivendell', NewRelic::Agent::Hostname.get
        end
      end

      def test_gcp_cloud_run_falls_back_to_socket_hostname_when_instance_id_unavailable
        NewRelic::Agent::Hostname.stubs(:gcp_instance_id).returns(nil)

        with_cloud_run_env('gcr-test.1', :'utilization.gcp_cloud_run.use_instance_as_host' => true) do
          assert_equal 'Rivendell', NewRelic::Agent::Hostname.get
        end
      end

      def test_gcp_instance_id_parses_successful_response
        Net::HTTP.stubs(:start).yields(stub(request: stub(code: '200', body: "1234567890\n")))

        assert_equal '1234567890', NewRelic::Agent::Hostname.gcp_instance_id
      end

      def test_gcp_instance_id_returns_nil_for_non_200_response
        Net::HTTP.stubs(:start).yields(stub(request: stub(code: '404', body: 'nope')))

        assert_nil NewRelic::Agent::Hostname.gcp_instance_id
      end

      def test_gcp_instance_id_returns_nil_on_connection_error
        Net::HTTP.stubs(:start).raises(Errno::ECONNREFUSED)

        assert_nil NewRelic::Agent::Hostname.gcp_instance_id
      end

      def with_cloud_run_env(revision, config_options)
        with_config(config_options) do
          ENV[NewRelic::Agent::Hostname::CLOUD_RUN_REVISION] = revision
          yield
        end
      ensure
        ENV.delete(NewRelic::Agent::Hostname::CLOUD_RUN_REVISION)
      end

      def test_local_predicate_true_when_host_local
        hosts = %w[localhost 0.0.0.0 127.0.0.1 0:0:0:0:0:0:0:1
          0:0:0:0:0:0:0:0 ::1 ::]

        hosts.each do |host|
          assert NewRelic::Agent::Hostname.local?(host)
        end
      end

      def test_localhost_predicate_false_when_host_nonlocal
        hosts = %w[drscheffler jonan-show jonan.tm]

        hosts.each do |host|
          refute NewRelic::Agent::Hostname.local?(host)
        end
      end

      def test_get_external_returns_host_for_localhost
        assert_equal 'Rivendell', NewRelic::Agent::Hostname.get_external('localhost')
      end

      def test_get_external_returns_argument_for_nonlocalhost
        assert_equal 'drscheffler', NewRelic::Agent::Hostname.get_external('drscheffler')
      end

      def with_dyno_name(dyno_name, config_options)
        with_config(config_options) do
          ENV['DYNO'] = dyno_name
          yield
        end
      ensure
        ENV.delete('DYNO')
      end

      # begin fqdn tests

      # allow the real fqdn determination code to fire and make sure it works
      def test_get_fqdn_no_stubs
        fqdn = NewRelic::Agent::Hostname.get_fqdn

        refute_equal '', fqdn
      end

      # 'hostname -f' succeeds
      def test_get_fqdn_hostname_f
        stubbed = +'Rivendell.Eriador.MiddleEarth'
        NewRelic::Helper.stubs('run_command').with('hostname -f').returns(stubbed)
        fqdn = NewRelic::Agent::Hostname.get_fqdn

        assert_equal stubbed, fqdn
      end

      # 'hostname -f' fails, 'hostname' succeeds
      def test_get_fqdn_hostname
        stubbed = +'Lauterbrunnen.Switzerland.Earth'
        NewRelic::Helper.stubs('run_command').with('hostname -f').raises(NewRelic::CommandRunFailedError)
        NewRelic::Helper.stubs('run_command').with('hostname').returns(stubbed)
        fqdn = NewRelic::Agent::Hostname.get_fqdn

        assert_equal stubbed, fqdn
      end

      # 'hostname -f' and 'hostname' both fail
      def test_get_fqdn_hostname_fails
        NewRelic::Helper.stubs('run_command').with('hostname -f').raises(NewRelic::CommandRunFailedError)
        NewRelic::Helper.stubs('run_command').with('hostname').raises(NewRelic::CommandRunFailedError)
        fqdn = NewRelic::Agent::Hostname.get_fqdn

        assert_equal 'Rivendell', fqdn # stubbed in 'setup' above
      end

      # the 'hostname' executable doesn't even exist
      def test_get_fqdn_hostname_nonexistent
        NewRelic::Helper.stubs('run_command').with('hostname -f').raises(NewRelic::CommandExecutableNotFoundError)
        fqdn = NewRelic::Agent::Hostname.get_fqdn

        assert_equal 'Rivendell', fqdn # stubbed in 'setup' above
      end

      # end fqdn tests
    end
  end
end
