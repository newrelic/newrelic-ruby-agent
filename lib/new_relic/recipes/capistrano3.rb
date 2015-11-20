# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'capistrano/framework'

namespace :newrelic do

  # notifies New Relic of a deployment
  desc "Record a deployment in New Relic (newrelic.com)"
  task :notice_deployment do
    run_locally do
      environment = fetch(:newrelic_rails_env, fetch(:rack_env, fetch(:rails_env, fetch(:stage, "production"))))

      require 'new_relic/cli/command.rb'

      begin
        # allow overrides to be defined for revision, description, changelog, appname, and user
        rev         = fetch(:newrelic_revision)
        description = fetch(:newrelic_desc)
        changelog   = fetch(:newrelic_changelog)
        appname     = fetch(:newrelic_appname)
        user        = fetch(:newrelic_user)
        license_key = fetch(:newrelic_license_key)

        unless scm == :none
          changelog ||= lookup_changelog
          rev       ||= fetch(:current_revision)
        end

        new_revision = rev
        deploy_options = {
          :environment => environment,
          :revision    => new_revision,
          :changelog   => changelog,
          :description => description,
          :appname     => appname,
          :user        => user,
          :license_key => license_key
        }

        debug "Uploading deployment to New Relic"
        deployment = NewRelic::Cli::Deployments.new deploy_options
        deployment.run
        info "Uploaded deployment information to New Relic"

      rescue NewRelic::Cli::Command::CommandFailure => e
        info e.message
      rescue => e
        info "Error creating New Relic deployment (#{e})\n#{e.backtrace.join("\n")}"
      end
    end
  end

  def lookup_changelog
    debug "Retrieving changelog for New Relic Deployment details"
    previous_revision = fetch(:previous_revision)
    current_revision = fetch(:current_revision)

    if scm == :git
      log_command = "git --no-pager log --no-color --pretty=format:'  * %an: %s' " +
                    "--abbrev-commit --no-merges #{previous_revision}..#{current_revision}"
      `#{log_command}`
    end
  end
end
