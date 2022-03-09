# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require 'new_relic/language_support'
require 'open3'

module NewRelic
  class CommandExecutableNotFoundError < StandardError; end
  class CommandRunFailedError < StandardError; end

  # A singleton for shared generic helper methods
  module Helper
    extend self

    # Confirm a string is correctly encoded,
    # If not force the encoding to ASCII-8BIT (binary)
    def correctly_encoded(string)
      return string unless string.is_a? String
      # The .dup here is intentional, since force_encoding mutates the target,
      # and we don't know who is going to use this string downstream of us.
      string.valid_encoding? ? string : string.dup.force_encoding(Encoding::ASCII_8BIT)
    end

    def instance_method_visibility(klass, method_name)
      if klass.private_instance_methods.map { |s| s.to_sym }.include? method_name.to_sym
        :private
      elsif klass.protected_instance_methods.map { |s| s.to_sym }.include? method_name.to_sym
        :protected
      else
        :public
      end
    end

    def instance_methods_include?(klass, method_name)
      method_name_sym = method_name.to_sym
      (
        klass.instance_methods.map { |s| s.to_sym }.include?(method_name_sym) ||
        klass.protected_instance_methods.map { |s| s.to_sym }.include?(method_name_sym) ||
        klass.private_instance_methods.map { |s| s.to_sym }.include?(method_name_sym)
      )
    end

    def time_to_millis(time)
      (time.to_f * 1000).round
    end

    def run_command(command)
      executable = command.split(' ').first
      raise NewRelic::CommandExecutableNotFoundError.new(executable) unless executable_in_path?(executable)

      output, status = Open3.capture2e(command)
      raise NewRelic::CommandRunFailedError.new(output) unless status.success?

      output.chomp
    end

    def executable_in_path?(executable)
      return false unless ENV['PATH']

      !ENV['PATH'].split(File::PATH_SEPARATOR).detect do |bin_path|
        executable_path = File.join(bin_path, executable)
        File.exist?(executable_path) && File.file?(executable_path) && File.executable?(executable_path)
      end.nil?
    end
  end
end
