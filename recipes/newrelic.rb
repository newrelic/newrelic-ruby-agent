# To be included in Capistrano deploy.rb files
#
# Defined deploy:notify_rpm which will send information about the deploy to RPM.
# The task will run on app servers except where no_release is true
#

Capistrano::Configuration.instance(:must_exist).load do
  
  namespace :deploy do
    # on all deployments, notify RPM 
    desc "Record a deployment in New Relic RPM (rpm.newrelic.com)"
    task :notify_rpm, :roles => :app, :except => {:no_release => true } do
      rails_env = fetch(:rails_env, "production")
      script = File.expand_path(File.join(File.dirname(__FILE__), "..","newrelic_api.rb"))
      run "cd #{current_release}; script/runner -e #{rails_env} #{script} -a #{application_id} -u '#{ENV['USER']}' '#{ENV['USER']} deploying #{File.basename(repository)}'"
    end
  end
end