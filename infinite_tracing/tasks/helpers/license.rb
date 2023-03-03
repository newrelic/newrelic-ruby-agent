# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module License
  def extract_license_terms(file_contents)
    text = []
    text << file_contents.shift while !file_contents.empty? && file_contents[0] =~ /^#/
    text << ''
    text
  end

  def add_license_preamble_and_remove_requires(output_path)
    gemspec_path = File.expand_path(File.join(output_path, '..', '..', '..', '..', '..'))
    license_terms = extract_license_terms(File.readlines(File.join(gemspec_path, 'Gemfile')))
    Dir.glob(File.join(output_path, '*.rb')) do |filename|
      contents = File.readlines(filename)
      contents.reject! { |r| r =~ /^\s*require\s.*$/ }
      File.open(filename, 'w') do |output|
        output.puts license_terms
        output.puts contents
      end
    end
  end
end
