# == REST API Helpers
#
# Ruby lib for working with the New Relic API's XML interface.  Requires Rails 2.0 or later to be loaded.
#
# Can also be used as a script using script/runner
#
# Authentication is handled using your agent license key or HTTP Basic Authentication.  To authenticate
# using your license key your newrelic.yml configuration file must be in your application config directory
# and contain your license key.  The New Relic account associated with the license key must allow api access.  
# Log into RPM, click Account at the top of the page and check the "Make my account data accessible" checkbox.
#
# Basic authentication uses your site credentials to authenticate.  
#
#   # To authenticate using basic authentication, make this call with your username and password:
#   NewRelicApi.authenticate('user@example.com', 'test')
#
# This API does not have any agent dependencies.  It can be used independent of the agent by copying it into your application.
#
# == Examples
#
#   # Fetching the list of applications for an account
#   NewRelicApi::Account.find(:first).applications
#  
#   # Fetching the health values for all account applications
#   NewRelicApi::Account.application_health
#
#   # Fetching the health values for an application
#   NewRelicApi::Account.find(:first).applications.first.threshold_values
#
#   # Finding an application by name
#   NewRelicApi::Account.find(:first).applications(:params => {:conditions => {:name => 'My App'}})
#

module NewRelicApi
  
  # This mixin defines ActiveRecord style associations (like has_many) for ActiveResource objects.
  # ActiveResource objects using this mixin must define the method 'query_params'. 
  module ActiveResourceAssociations #:nodoc:
    class << self
      protected
      def included(base)
        class << base
          # a special activeresource implementation of has_many
          def has_many(*associations)
            associations.to_a.each do |association|
              define_method association do |*args|
                val = attributes[association.to_s] # if we've already fetched the relationship in the initial fetch, return it
                return val if val
                
                options = args.extract_options!
                type = args.first || :all
                
                begin
                  # look for the class definition within the current class
                  clazz = ( self.class.name + '::' + association.to_s.camelize.singularize).constantize
                rescue
                  # look for the class definition in the NRAPI module
                  clazz = ( 'NewRelicApi::' + association.to_s.camelize.singularize).constantize
                end
                params = (options[:params] || {}).update(self.query_params)
                options[:params] = params
                clazz.find(type, options)
                
                #clazz.find(type, :params => options.update(self.query_params))
              end
            end
          end          
        end
      end
    end
    
  end
  class << self
    attr_accessor :email, :password, :license_key, :ssl, :host, :port
    
    # Sets up basic authentication credentials for all the resources.  This is not necessary if you are
    # using agent license key authentication.
    def authenticate(email, password)
      @password = password
      @email    = email
    end
    
    # Resets the base path of all resources.  This should be called when overridding the newrelic.yml settings
    # using the ssl, host or port accessors.
    def reset!
      @classes.each {|klass| klass.reset!} if @classes
      NewRelicApi::Account.site_url
    end
    
    
    def track_resource(klass) #:nodoc:
      (@classes ||= []) << klass
    end
  end
  class BaseResource < ActiveResource::Base #:nodoc:
    include ActiveResourceAssociations

    class << self
      def inherited(klass) #:nodoc:
        NewRelicApi.track_resource(klass)
      end
      
      def headers
        h = {'x-license-key' => NewRelicApi.license_key || NewRelic::Control.instance['license_key']}
        h['Authorization'] = 'Basic ' + ["#{NewRelicApi.email}:#{NewRelicApi.password}"].pack('m').delete("\r\n") if NewRelicApi.email
        h
      end
      
      def site_url
        host = NewRelicApi.host || NewRelic::Control.instance.api_server.name
        port = NewRelicApi.port || NewRelic::Control.instance.api_server.port
        "#{port == 443 ? 'https' : 'http'}://#{host}:#{port}"
      end
      
      def reset!
        self.site = self.site_url
      end
      
      protected
      
      def fix_fields(*fields)
        fields.to_a.each do |field|
          define_method field do
            yield super
          end
        end
      end
      
      def fix_integer_fields(*fields)
        fix_fields(*fields) { |sup| sup.to_i }
      end
      
      def fix_float_fields(*fields)
        fix_fields(*fields) { |sup| sup.to_f }
      end
      
    end
    self.site = self.site_url
  end
  ACCOUNT_RESOURCE_PATH = '/accounts/:account_id/' #:nodoc:
  ACCOUNT_AGENT_RESOURCE_PATH = ACCOUNT_RESOURCE_PATH + 'agents/:agent_id/' #:nodoc:
  ACCOUNT_APPLICATION_RESOURCE_PATH = ACCOUNT_RESOURCE_PATH + 'applications/:application_id/' #:nodoc:
  
  module AccountResource #:nodoc: 
    def account_id
      prefix_options[:account_id]
    end
    def account_query_params(extra_params = {})
      {:account_id => account_id}.merge(extra_params)
    end
    
    def query_params#:nodoc:
      account_query_params
    end 
  end
  
  module AgentResource #:nodoc:
    include ActiveResourceAssociations
  end
    
  # An application has many:
  # +agents+:: the agent instances associated with this app
  # +threshold_values+:: the health indicators for this application.
  class Application < BaseResource
    include AccountResource
    include AgentResource
    
    has_many :agents, :threshold_values
    
    self.prefix = ACCOUNT_RESOURCE_PATH
    
    def query_params#:nodoc:
      account_query_params(:application_id => id)
    end
    
    class Agent < BaseResource
      include AccountResource
      include AgentResource
      
      self.prefix = ACCOUNT_APPLICATION_RESOURCE_PATH
      
      def query_params#:nodoc:
        super.merge(:application_id => cluster_agent_id)
      end
    end
    
  end
  
  # A threshold value represents a single health indicator for an application such as CPU, memory or response time.
  #
  # ==Fields
  # +name+:: The name of the threshold setting associated with this threshold value.
  # +threshold_value+:: A value of 0, 1, 2 or 3 representing gray (not reporting), green, yellow and red
  # +metric_value+:: The metric value associated with this threshold
  class ThresholdValue < BaseResource
    self.prefix = ACCOUNT_APPLICATION_RESOURCE_PATH
    #      attr_reader :name, :begin_time, :metric_value, :threshold_value
    
    fix_integer_fields :threshold_value
    fix_float_fields :metric_value
    
    # Returns the color value for this threshold (Gray, Green, Yellow or Red).
    def color_value
      case threshold_value
        when 3: 'Red'
        when 2: 'Yellow'
        when 1: 'Green'
      else 'Gray'
      end
    end
    
    def to_s #:nodoc:
      "#{name}: #{color_value} (#{formatted_metric_value})"
    end
  end
  
  # An account contains your basic account information.
  #
  # Accounts have many
  # +applications+:: the applications contained within the account
  # 
  # Find Accounts
  #
  #   NewRelicApi::Account.find(:all) # find all accounts for the current user.
  #   NewRelicApi::Account.find(44)   # find individual account by ID
  #
  class Account < BaseResource
    has_many :applications
    has_many :account_views
    
    def query_params #:nodoc:
      {:account_id => id}
    end
    
    # Returns an account including all of its applications and the threshold values for each application.
    def self.application_health(type = :first)
      find(type, :params => {:include => :application_health})
    end
    
    # Add a user to an account.
    # +user_params+:: User parameters as a hash consisting of the following:
    #                 email, first_name, password, password_confirmation
    #                 If a user record already exists for this email, the name
    #                 and password fields are ignored.
    # +is_admin+:: Set administrative privileges for this user.
    def add_user(user_params, is_admin = false)
      account_id = self.id
      account_view = NewRelicApi::Account::AccountView.create(:account_id => account_id, :user => user_params, :is_admin => is_admin)
      account_views << account_view if account_view.valid?
      account_view    
    end
    
    # Change the subscription for an account
    # +product_id+:: ID or name of product (e.g. Lite) (required).
    # +number_of_hosts+:: Number of hosts. This is required for fixed host products.
    #                     For utility based products, this is set to the maximum
    #                     number of hosts allowed to connect.
    def change_subscription(sub_params)
      NewRelicApi::Subscription.create(sub_params.merge(:account_id => self.id))
    end
    
    # Remove a user's access from an account.
    # +email+:: User's email address.
    def remove_user(email)
      view = NewRelicApi::Account::AccountView.find(:one, :params => {:account_id => self.id, :email => email})
      view.destroy if view
    end
    
    # Change the primary admin for an account. The administrator must be a 
    # user that is already associated with the account
    # +email+:: Email address of the new administrator
    def change_primary_admin(email)
      put(:update_primary_admin, :email => email)
    end
    
    class AccountView < BaseResource
      self.prefix = ACCOUNT_RESOURCE_PATH
      
      def query_params(extra_params = {}) #:nodoc:
        {:account_id => account_id}.merge(extra_params)
      end
      
      def user
        @attributes['user']
      end
    end      
  end
    
  # This model is used to mark production deployments in RPM
  # Only create is supported.
  # ==Examples
  #   # Creating a new deployment
  #   NewRelicApi::Deployment.create
  #
  class Deployment < BaseResource
  end
  
  # This model is used to modify subscriptions for existing accounts in RPM.
  # To update a subscription, create a new instance with the following properties:
  # +account_id+:: Account ID in RPM (required).
  # +product_id+:: ID or name of product (e.g. Lite) (required).
  # +number_of_hosts+:: Number of hosts. This is required for fixed host products.
  #                     For utility based products, this is set to the maximum
  #                     number of hosts allowed to connect.
  class Subscription < BaseResource
    def query_params(extra_params = {}) #:nodoc:
      {:account_id => account_id}.merge(extra_params)
    end
  end

  class User < BaseResource
  end

end

