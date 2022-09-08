# frozen_string_literal: true

require 'thor'

class Instrumentation < Thor
  include Thor::Actions

  desc('scaffold NAME', 'Scaffold the required files for adding new instrumentation')
  long_desc <<-LONGDESC
    `instrumentation scaffold` requires one parameter by default: the name of the
    library or class you are instrumenting. This task generates the basic
    file structure needed to add new instrumentation to the Ruby agent.
  LONGDESC

  source_root(File.dirname(__FILE__))

  option :method,
    default: 'method_to_instrument',
    desc: 'The method you would like to prepend or chain instrumentation onto'
  option :args,
    default: '*args',
    desc: 'The arguments associated with the original method'

  def scaffold(name)
    @name = name
    @method = options[:method] if options[:method]
    @args = options[:args] if options[:args]
    base_path = "lib/new_relic/agent/instrumentation/#{name.downcase}"
    empty_directory(base_path)

    ['chain', 'instrumentation', 'prepend'].each do |file|
      template("templates/#{file}.tt", "#{base_path}/#{file}.rb")
    end

    template('templates/dependency_detection.tt', "#{base_path}.rb")
    create_configuration(name)
    create_tests(name)
  end

  desc 'add_new_method NAME', 'Inserts a new method into an existing piece of instrumentation'

  option :method, required: true, desc: 'The name of the method to instrument'
  option :args, default: '*args', desc: 'The arguments associated with the instrumented method'

  def add_new_method(name, method_name)
    # Verify that existing instrumentation exists
    # if it doesn't, should we just call the #scaffold method instead since we have all the stuff
    # otherwise, inject the new method into the instrumentation matching the first arg
    # add to only chain, instrumentation, prepend
    # move the method content to a partial
  end

  private

  def create_tests(name)
    @name = name
    base_path = "test/multiverse/suites/#{@name.downcase}"
    empty_directory(base_path)
    template('templates/Envfile.tt', "#{base_path}/Envfile")
    template('templates/test.tt', "#{base_path}/#{@name.downcase}_instrumentation_test.rb")

    empty_directory("#{base_path}/config")
    template('templates/newrelic.yml.tt', "#{base_path}/config/newrelic.yml")
  end

  def create_configuration(name)
    config = <<-CONFIG
        :'instrumentation.#{name.downcase}' => {
          :default => "auto",
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of the #{name.capitalize} library at start up. May be one of [auto|prepend|chain|disabled].'
        },
    CONFIG
    insert_into_file(
      'lib/new_relic/agent/configuration/default_source.rb',
      config,
      after: ":description => 'Controls auto-instrumentation of bunny at start up.  May be one of [auto|prepend|chain|disabled].'
        },\n"
    )
  end
end

Instrumentation.start(ARGV)
