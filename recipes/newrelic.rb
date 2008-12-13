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
      # I don't believe this will work if rpm is installed as a gem, or 
      # if they put the plugin elsewhere.  Need to revisit.
      script = [ "vendor/plugins/newrelic_rpm/lib/newrelic_api.rb" ] <<
                 "deployments" <<
                 "-u" << ENV['USER'] <<
                 "deploying #{File.basename(repository)}"
      script = script.map { | arg | "'#{arg}'" }.join(" ")
      begin
        run "cd #{current_release}; #{log_command} | script/runner -e #{rails_env} #{script}" do | ssh, stream_id, output |
          logger.trace(output)
        end
      rescue CommandError
        logger.info "unable to notify New Relic of the deployment... skipping"
      end
      # For rollbacks, let's update the deployment we created with an indication of the failure:
      #on_rollback do
      #  run(command.gsub(/Subject:.*\\n/, "Subject: #{ENV['USER']} deployed a ROLLBACK\\n"))
      #end
    end
  end
end

instance = Capistrano::Configuration.instance
if instance
  instance.load make_notify_task
else
  make_notify_task.call
end
