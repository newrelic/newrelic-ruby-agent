# This is a class for executing commands related to deployment 
# events

require 'optparse'
require 'newrelic_api'
module NewRelic::API
  class Deployments
    def initialize command_line_args
      @application_id = NewRelic::Config.instance.app_name || RAILS_ENV
      @user = ENV['USER']
      description = options.parse command_line_args
      help("Description missing.") if description.blank?
    end
    def run
      # create a Deployment in RPM via Active Resource
      begin
        d = NewRelicAPI::Deployment.create(:agent_id => @application_id, :description => description)
        if d.valid?
          puts "Recorded deployment to NewRelic RPM (#{d.description})"
        else
          STDERR.puts "Could not record deployment to NewRelic RPM:"
          STDERR.puts d.errors.full_messages.join("\n")
          exit 1
        end
      rescue Exception => e
        STDERR.puts "Unable to upload deployment (#{e.message})"
        STDERR.puts e.backtrace.join("\n")
      end
    end
    
    def options
      OptionParser.new do |o|
        o.set_summary_indent('  ')
        o.banner =    "Usage: deployments [OPTIONS] description "
        o.define_head "RPM Deployments CLI"
        o.on("-a", "--appname=DIR", String,
             "Specify an application name.",
             "Default: #{application_id}") { |@application_id| }
        o.on("-u", "--user=USER", String,
             "Specify the user deploying.",
             "Default: #{ENV['USER']}") { |@user| }
        o.on("-h", "--help", "Print this help") { puts o; exit }
        o.separator "description = short text"
      end
    end
    
    def help(message)
      if message
        STDERR.puts message
        STDERR.puts options
        exit 1
      else
        STDOUT.puts options
        exit 0
      end
    end
  end
end