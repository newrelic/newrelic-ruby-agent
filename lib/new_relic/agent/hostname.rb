# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'socket'
require 'new_relic/helper'

module NewRelic
  module Agent
    module Hostname
      # Cloud Run sets a different revision variable per resource type: K_REVISION
      # on a Service, CLOUD_RUN_REVISION on a Worker Pool, and CLOUD_RUN_EXECUTION
      # on a Job. Only one is ever set, so the first non-empty value both identifies
      # Cloud Run and names the revision.
      # https://docs.cloud.google.com/run/docs/container-contract#env-vars
      CLOUD_RUN_REVISION_VARS = %w[K_REVISION CLOUD_RUN_REVISION CLOUD_RUN_EXECUTION].freeze
      GCP_INSTANCE_ID_URI = 'http://metadata.google.internal/computeMetadata/v1/instance/id'
      GCP_METADATA_HEADERS = {'Metadata-Flavor' => 'Google'}.freeze

      def self.get
        dyno_name = ENV['DYNO']
        @hostname ||= if dyno_name && ::NewRelic::Agent.config[:'heroku.use_dyno_names']
          matching_prefix = heroku_dyno_name_prefix(dyno_name)
          dyno_name = "#{matching_prefix}.*" if matching_prefix
          dyno_name
        elsif gcp_cloud_run?
          gcp_cloud_run_host
        else
          Socket.gethostname.force_encoding(Encoding::UTF_8)
        end
      end

      def self.gcp_cloud_run?
        !cloud_run_revision.nil? &&
          ::NewRelic::Agent.config[:'utilization.gcp_cloud_run.use_instance_as_host']
      end

      # The revision (Service, Worker Pool) or execution (Job) name for the
      # Cloud Run resource this process belongs to, or nil when not on Cloud Run.
      def self.cloud_run_revision
        CLOUD_RUN_REVISION_VARS.map { |var| ENV[var] }.find { |value| value && !value.empty? }
      end

      def self.gcp_cloud_run_host
        instance_id = gcp_instance_id
        return Socket.gethostname.force_encoding(Encoding::UTF_8) unless instance_id

        if ::NewRelic::Agent.config[:'utilization.gcp_cloud_run.include_revision_in_host']
          "#{cloud_run_revision}-#{instance_id}"
        else
          instance_id
        end
      end

      def self.gcp_instance_id
        response = NewRelic::Helper.fetch_metadata(GCP_INSTANCE_ID_URI, GCP_METADATA_HEADERS)
        return unless response&.code == '200'

        id = response.body.to_s.strip
        id.empty? ? nil : id
      rescue => e
        NewRelic::Agent.logger.debug("Unable to fetch GCP Cloud Run instance id: #{e.class} - #{e.message}")
        nil
      end

      # Pass '-f' to the external executable 'hostname' to request the fully
      # qualified domain name (fqdn). For implementations of 'hostname' that
      # do not support '-f' (such as the one OpenBSD ships with), fall back
      # to calling 'hostname' without the '-f'. If both ways of calling
      # 'hostname' fail, or in a context where 'hostname' is not even
      # available (within an AWS Lambda function, for example), call the
      # 'get' method which uses Socket instead of an external executable.
      def self.get_fqdn
        begin
          NewRelic::Helper.run_command('hostname -f')
        rescue NewRelic::CommandRunFailedError
          NewRelic::Helper.run_command('hostname')
        end
      rescue NewRelic::CommandExecutableNotFoundError, NewRelic::CommandRunFailedError => e
        NewRelic::Agent.logger.debug("#{e.class} - #{e.message}")
        get
      end

      def self.heroku_dyno_name_prefix(dyno_name)
        get_dyno_prefixes.find do |dyno_prefix|
          dyno_name.start_with?(dyno_prefix + '.')
        end
      end

      def self.get_dyno_prefixes
        ::NewRelic::Agent.config[:'heroku.dyno_name_prefixes_to_shorten']
      end

      LOCALHOST = %w[
        localhost
        0.0.0.0
        127.0.0.1
        0:0:0:0:0:0:0:1
        0:0:0:0:0:0:0:0
        ::1
        ::
      ].freeze

      def self.local?(host_or_ip)
        LOCALHOST.include?(host_or_ip)
      end

      def self.get_external(host_or_ip)
        local?(host_or_ip) ? get : host_or_ip
      end
    end
  end
end
