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
      # I don't believe this will work if rpm is installed as a gem
      script = "newrelic_api.rb"
      begin
        run "cd #{current_release}; script/runner -e #{rails_env} #{script} deployments -u '#{ENV['USER']}' '#{ENV['USER']} deploying #{File.basename(repository)}'" do | ssh, stream_id, output |
          logger.trace(output)
        end
      rescue CommandError
        logger.important "unable to notify New Relic of the deployment... skipping"
      end
    end
  end
end

instance = Capistrano::Configuration.instance
if instance
  instance.load make_notify_task
else
  make_notify_task.call
end
