# This is a class for executing commands related to deployment 
# events.  It runs without loading the rails environment

$LOAD_PATH << File.expand_path(File.join(File.dirname(__FILE__),"..",".."))
require 'yaml'
require 'net/http'

# We need to use the Config object but we don't want to load 
# the rails/merb environment.  The defined? clause is so that
# it won't load it twice, something it does when run inside a test
require 'new_relic/config' unless defined? NewRelic::Config

module NewRelic
  module Commands
    class Deployments
      
      attr_reader :config
      def self.command; "deployments"; end 
      
      # Initialize the deployment uploader with command line args.
      # Use -h to see options.  Will possibly exit the VM 
      def initialize command_line_args
        @config = NewRelic::Config.instance
        @user = ENV['USER']
        @description = options.parse(command_line_args).join " "
        @application_id ||= config.app_name || config.env || 'development'
      end
      
      # Run the Deployment upload in RPM via Active Resource.
      # Will possibly print errors and exit the VM
      def run
        begin
          @description = nil if @description.empty?
          create_params = {}
          {
            :application_id => @application_id, 
            :host => Socket.gethostname, 
            :description => @description,
            :user => @user,
            :revision => @revision,
            :changelog => @changelog
          }.each do |k, v|
            create_params["deployment[#{k}]"] = v unless v.nil? || v == ''
          end
          http = config.http_connection(config.api_server)
          
          uri = "/deployments.xml"

					raise "license_key was not set in newrelic.yml for #{config.env}" if config['license_key'].nil?
          request = Net::HTTP::Post.new(uri, 'HTTP_X_LICENSE_KEY' => config['license_key'])
          request.content_type = "application/octet-stream"

          request.set_form_data(create_params)
          
          response = http.request(request)
          
          if response.is_a? Net::HTTPSuccess
            info "Recorded deployment to NewRelic RPM (#{@description || Time.now })"
          else
            err "Unexpected response from server: #{response.code}: #{response.message}"
            # TODO look for errors in xml response
            just_exit -1
          end 
        rescue SystemCallError, SocketError => e
          # These include Errno connection errors 
          err "Transient error attempting to connect to #{config.api_server} (#{e})"
          just_exit -2
        rescue Exception => e
          err "Unexpected error attempting to connect to #{config.api_server} (#{e})"
          info e.backtrace.join("\n")
          just_exit 1
        end
      end
      
      private
      
      def options
        OptionParser.new "Usage: #{self.class.command} [OPTIONS] [description] ", 40 do |o|
          o.separator "OPTIONS:"
          o.on("-a", "--appname=DIR", String,
             "Set the application name.",
             "Default is app_name setting in newrelic.yml") { |@application_id| }
          o.on("-e ENV", String,
               "Override the (RAILS|MERB|RUBY)_ENV setting",
               "currently: #{config.env}") { |env| config.env=env }
          o.on("-u", "--user=USER", String,
             "Specify the user deploying.",
             "Default: #{@user}") { |@user| }
          o.on("-r", "--revision=REV", String,
             "Specify the revision being deployed") { |@revision | }
          o.on("-c", "--changes", 
             "Read in a change log from the standard input") { @changelog = STDIN.read }
          o.on("-?", "Print this help") { info o.help; just_exit }
          o.separator ""
          o.separator 'description = "short text"'
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
end