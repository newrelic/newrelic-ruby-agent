# frozen_string_literal: true
require 'securerandom'

random = SecureRandom.uuid
SimpleCov.command_name(random)
SimpleCov.coverage_dir("coverage_#{random}")

SimpleCov.start do
  enable_coverage :branch
  SimpleCov.root(File.join(File.dirname(__FILE__), '/lib'))
  track_files "**/*.rb"
end
