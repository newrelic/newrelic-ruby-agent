# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'helpers/license'
include License

namespace :proto do
  desc 'Generate proto files'
  task :generate do
    gem_folder = File.expand_path(File.join(File.dirname(__FILE__), '..'))
    proto_filename = File.join(gem_folder, 'lib', 'new_relic', 'proto', 'infinite_tracing.proto')
    output_path = File.join(gem_folder, 'lib', 'new_relic', 'infinite_tracing', 'proto')

    FileUtils.mkdir_p(output_path)
    cmd = [
      'grpc_tools_ruby_protoc',
      "-I#{gem_folder}/lib/new_relic/proto",
      "--ruby_out=#{output_path}",
      "--grpc_out=#{output_path} #{proto_filename}"
    ].join(' ')

    if system(cmd)
      puts 'Proto file generated!'
      add_license_preamble_and_remove_requires(output_path)
    else
      puts 'Failed to generate proto file.'
    end
  end
end
