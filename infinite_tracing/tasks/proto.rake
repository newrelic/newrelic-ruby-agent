# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

namespace :proto do
  desc "Generate proto files"

  task :generate do
    def extract_license_terms file_contents
      text = []
      text << file_contents.shift while !file_contents.empty? && file_contents[0] =~ /^#/
      text << ""
      text
    end

    # adds the NewRelic License notice to the top of the generated files
    # Removes require lines since these are replicated in the proto.rb file.
    def add_license_preamble_and_remove_requires output_path
      gemspec_path = File.expand_path(File.join(output_path, '..', '..', '..', '..'))
      license_terms = extract_license_terms File.readlines(File.join(gemspec_path, "Gemfile"))
      Dir.glob(File.join output_path, "*.rb") do |filename|
        contents = File.readlines filename
        contents.reject!{|r| r =~ /^\s*require\s.*$/}
        File.open(filename, 'w') do |output|
          output.puts license_terms
          output.puts contents
        end
      end
    end

    gem_folder = File.expand_path File.join(File.dirname(__FILE__), "..")
    proto_filename = File.join gem_folder, "lib", "proto", "infinite_tracing.proto"
    output_path = File.join gem_folder, "lib", "infinite_tracing", "proto"

    FileUtils.mkdir_p output_path
    cmd = [
      "grpc_tools_ruby_protoc",
      "-I#{gem_folder}/lib/proto",
      "--ruby_out=#{output_path}",
      "--grpc_out=#{output_path} #{proto_filename}"
    ].join(" ")

    if system cmd
      puts "Proto file generated!"
      add_license_preamble_and_remove_requires output_path
    else
      puts "Failed to generate proto file."
    end
  end

end
