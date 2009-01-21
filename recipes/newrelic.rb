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
      from_revision = source.next_revision(current_revision)
      log_command = source.log(from_revision)
      # Because new_relic_api could be plugins or the gem dir, we rely
      # on the lib path to find it. 
      ## script = [ ' ] <<
      script = [ 'vendor/plugins/newrelic_rpm/bin/newrelic_cmd' ] <<
                 "deployments" <<
                 "-u" << ENV['USER'] <<
                 "-e" << rails_env <<
                 "-r" << current_revision <<
                 "-c"
      
      script = script.map { | arg | "'#{arg}'" }.join(" ")
      begin
        run "cd #{current_release}; #{log_command} | ruby #{script}" do | io, stream_id, output |
          logger.trace(output)
        end
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
