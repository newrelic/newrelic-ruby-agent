# This is a class for executing commands related to deployment 
# events

require 'optparse'

module NewRelic::API
  
  class Deployments
    
    def self.command; "deployments"; end 
      
    # Initialize the deployment uploader with command line args.
    # Use -h to see options.  Will possibly exit the VM 
    def initialize command_line_args
      @application_id = NewRelic::Config.instance.app_name || RAILS_ENV
      @user = ENV['USER']
      @description = options.parse(command_line_args).join " "
    end
    
    # Run the Deployment upload in RPM via Active Resource.
    # Will possibly print errors and exit the VM
    def run
      begin
        @description = nil if @description.blank?
        create_params = {
          :application_id => @application_id, 
          :host => Socket.gethostname, 
          :description => @description,
          :user => @user,
          :revision => @revision,
          :changelog => @changelog
        }
        d = NewRelicAPI::Deployment.create(create_params)
      rescue Exception => e
        err "Attempting to connect to #{NewRelicAPI::BaseResource.site_url}\nUnable to upload deployment (#{e.message})"
        info e.backtrace.join("\n")
        just_exit 1
      end
      if d.nil?
        err "No value returned from create!"
        just_exit 1
      elsif d.valid?
        puts "Recorded deployment to NewRelic RPM (#{d.description})"
      else
        err "Could not record deployment to NewRelic RPM:"
        err d.errors.full_messages.join("\n")
        just_exit 1
      end
    end
    
    private
    
    def options
      OptionParser.new "Usage: #{self.class.command} [OPTIONS] [description] ", 40 do |o|
        o.separator "OPTIONS:"
        o.on("-a", "--appname=DIR", String,
             "Specify an application name.",
             "Default: #{@application_id}") { |@application_id| }
        o.on("-u", "--user=USER", String,
             "Specify the user deploying.",
             "Default: #{ENV['USER']}") { |@user| }
        o.on("-r", "--revision=REV", String,
             "Specify the revision being deployed") { |@revision | }
        o.on("-c", "--changes", 
             "Read in a change log from the standard input") { @changelog = STDIN.read }
        o.on("-?", "Print this help") { info o.help; just_exit }
        o.separator ""
        o.separator 'description = "short text"'
      end
    end
    
    def help(message)
      if message
        err message
        info options.help
        just_exit 1
      else
        info options
        just_exit 0
      end
    end
    def info message
      STDOUT.puts message
    end
    def err message
      STDERR.puts message
    end  
    def just_exit status=0
      exit status
    end
  end
end