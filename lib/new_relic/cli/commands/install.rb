# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'fileutils'
require 'new_relic/version'
require 'erb'

class NewRelic::Cli::Install < NewRelic::Cli::Command

  NO_LICENSE_KEY = "<PASTE LICENSE KEY HERE>"
  CONFIG_FILENAME = "newrelic.yml"

  def self.command; "install"; end

  # Use -h to see options.
  # When command_line_args is a hash, we are invoking directly and
  # it's treated as an options with optional string values for
  # :user, :description, :appname, :revision, :environment,
  # and :changes.
  #
  # Will throw CommandFailed exception if there's any error.
  #
  attr_reader :dest_dir, :license_key, :generated_for_user, :quiet, :src_file,
              :dest_file, :app_name
  def initialize command_line_args={}
    super command_line_args
    @dest_dir ||= default_destination_directory
    @license_key ||= NO_LICENSE_KEY
    @app_name ||= @leftover
    check_for_app_name_presence
    @generated_for_user ||= @user_string || ""
  end

  def run
    check_if_config_file_presence
    create_config_file
    installation_sucess_message
    warning_if_no_license_key
    support_info_message
  end

  private

  def create_config_file
    File.open(dest_file, 'w') { | out | out.puts(content) }
  end

  def content
    template = File.read(src_file)
    ERB.new(template).result(binding)
  end

  def check_if_config_file_presence
    if File.exist?(dest_file)
      raise NewRelic::Cli::Command::CommandFailure, "#{CONFIG_FILENAME} file already exists.  Move it out of the way."
    end
  end

  def src_file
    @src_file ||= File.expand_path(File.join(File.dirname(__FILE__),"..","..","..","..","#{CONFIG_FILENAME}"))
  end

  def dest_file
    @dest_file = File.expand_path(@dest_dir + "/#{CONFIG_FILENAME}")
  end

  def installation_sucess_message
    puts <<-EOF unless quiet

Installed a default configuration file at
#{dest_file}.
    EOF
  end

  def warning_if_no_license_key
    puts <<-EOF unless quiet || @license_key != NO_LICENSE_KEY

To monitor your application in production mode, sign up for an account
at www.newrelic.com, and replace the newrelic.yml file with the one
you receive upon registration.
    EOF
  end

  def support_info_message
    puts <<-EOF unless quiet

Visit support.newrelic.com if you are experiencing installation issues.
    EOF
  end

  # Install a newrelic.yml file into the local config directory.
  def default_destination_directory
    File.directory?("config") ? "config" : "."
  end

  def check_for_app_name_presence
    raise CommandFailure.new("Application name required.", @options) unless app_name && app_name.size > 0
  end

  def options
    OptionParser.new "Usage: #{$0} #{self.class.command} [OPTIONS] 'application name'", 40 do |o|
      o.on("-l", "--license_key=KEY", String,
        "Use the given license key") { | e | @license_key = e }
      o.on("-d", "--destdir=name", String,
        "Write the newrelic.yml to the given directory, default is './config' and '.' ") { | e | @dest_dir = e }
      yield o if block_given?
    end
  end

end
