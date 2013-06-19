# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'dependency_detection/version'
module DependencyDetection

  module_function
  @items = []
  def defer(&block)
    item = Dependent.new
    item.instance_eval(&block)
    @items << item
  end

  def detect!
    @items.each do |item|
      if item.dependencies_satisfied?
        item.execute
      end
    end
  end

  def dependency_by_name(name)
    @items.find {|i| i.name == name }
  end

  def installed?(name)
    item = dependency_by_name(name)
    item && item.executed
  end

  def items
    @items
  end

  def items=(new_items)
    @items = new_items
  end

  class Dependent
    attr_reader :executed
    attr_reader :name
    def executed!
      @executed = true
    end

    attr_reader :dependencies

    def initialize
      @dependencies = []
      @executes = []
    end

    def dependencies_satisfied?
      !executed and check_dependencies
    end

    def execute
      @executes.each do |x|
        x.call
      end
    ensure
      executed!
    end

    def check_dependencies
      dependencies && dependencies.all? { |d| d.call }
    end

    def depends_on
      @dependencies << Proc.new
    end

    def named(new_name)
      name = new_name
      depends_on do
        key = "disable_#{new_name}".to_sym
        if (::NewRelic::Agent.config[key] == true)
          ::NewRelic::Agent.logger.debug("Not installing #{new_name} instrumentation because of configuration #{key}")
          false
        else
          true
        end
      end
    end

    def executes
      @executes << Proc.new
    end
  end
end
