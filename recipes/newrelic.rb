# To be included in Capistrano deploy.rb files
#
# Defined deploy:notify_rpm which will send information about the deploy to RPM.
# The task will run on app servers except where no_release is true.
# If it fails, it will not affect the task execution or do a rollback.
#

make_notify_task = lambda do
  
  namespace :newrelic do
    
    # on all deployments, notify RPM 
    desc "Record a deployment in New Relic RPM (rpm.newrelic.com)"
    task :notice_deployment, :roles => :app, :except => {:no_release => true } do
      rails_env = fetch(:rails_env, "production")
      begin
        require File.expand_path(File.join(File.dirname(__FILE__),'../lib/new_relic/commands/deployments.rb'))
        # Try getting the changelog from the server.  Then fall back to local changelog
        # if it doesn't work.  Problem is that I don't know what directory the .git is
        # in when using git.
=begin        
        run "cd #{current_release}; #{log_command}" do | io, stream_id, output |
          changelog = output
        end
=end
        # allow overrides to be defined for description, changelog and appname
        description = newrelic_desc rescue nil
        changelog = newrelic_changelog rescue nil
        appname = newrelic_appname rescue nil
        if !changelog
          from_revision = source.next_revision(current_revision)
          log_command = "#{source.log(from_revision)}"
          logger.info "Executing #{log_command}"
          changelog = `#{log_command}`
        end
        deploy_options = { :environment => rails_env,
                :revision => current_revision, 
                :changelog => changelog, 
                :description => description,
                :appname => appname }
        deployment = NewRelic::Commands::Deployments.new deploy_options
        deployment.run
        logger.info "uploaded deployment"
      rescue ScriptError => e
        logger.info "error creating New Relic deployment (#{e})\n#{e.backtrace.join("\n")}"
      rescue NewRelic::Commands::CommandFailure => e
        logger.info "unable to notify New Relic of the deployment (#{e})... skipping"
      rescue CommandError
        logger.info "unable to notify New Relic of the deployment... skipping"
      end
      # WIP: For rollbacks, let's update the deployment we created with an indication of the failure:
      # on_rollback do
      #   run(...)
      # end
    end
  end
end

instance = Capistrano::Configuration.instance
if instance
  instance.load make_notify_task
else
  make_notify_task.call
end
