# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.


module NewRelic
  module Agent
    module Connect

      class RequestBuilder

        def initialize(new_relic_service, config)
          @service = new_relic_service
          @config = config
        end


        # Initializes the hash of settings that we send to the
        # server. Returns a literal hash containing the options
        def connect_payload
          {
            :pid           => $$,
            :host          => local_host,
            :display_host  => Agent.config[:'process_host.display_name'],
            :app_name      => Agent.config.app_names,
            :language      => 'ruby',
            :labels        => Agent.config.parsed_labels,
            :agent_version => NewRelic::VERSION::STRING,
            :environment   => sanitize_environment_report(environment_report),
            :settings      => Agent.config.to_collector_hash,
            :high_security => Agent.config[:high_security],
            :utilization   => UtilizationData.new.to_collector_hash,
            :identifier    => "ruby:#{local_host}:#{Agent.config.app_names.sort.join(',')}"
          }
        end

        # We've seen objects in the environment report (Rails.env in
        # particular) that can't seralize to JSON. Cope with that here and
        # clear out so downstream code doesn't have to check again.
        def sanitize_environment_report(environment_report)
          return [] unless @service.valid_to_marshal?(environment_report)
          environment_report
        end

        # Checks whether we should send environment info, and if so,
        # returns the snapshot from the local environment.
        # Generating the EnvironmentReport has the potential to trigger
        # require calls in Rails environments, so this method should only
        # be called synchronously from on the main thread.
        def environment_report
          Agent.config[:send_environment_info] ? Array(EnvironmentReport.new) : []
        end

        def local_host
          NewRelic::Agent::Hostname.get
        end
      end

      class ResponseHandler

      end
    end
  end
end
