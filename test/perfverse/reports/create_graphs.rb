# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'charty'
require 'zip'
require 'matplotlib'

Charty::Backends.use(:pyplot)
Matplotlib.use(:agg)

CSV_SKIP_LAST = 15
CSV_SKIP_FIRST = 6

# currently only used for dockermon csv files
def read_csv(file_path, agent_version, data)
  max_line_count = %x(wc -l "#{file_path}").split.first.to_i - CSV_SKIP_LAST

  File.open(file_path, 'r') do |f|
    headers = f.readline.split(',').map(&:strip)
    headers.each { |header| data[header.to_sym] ||= [] }

    f.each_line.with_index do |line, index|
      next if index <= CSV_SKIP_FIRST # skip the container starting up
      break if index >= max_line_count # skip the container shutting down

      data[:agent_version] << agent_version
      values = line.split(',')
      headers.each_with_index do |header, index|
        val = values[index]
        val = val.to_f unless header.to_sym == :"Container Name"
        data[header.to_sym] << val
      end
    end
  end
  data
end

# unzips everything and deletes the zip folder
def unzip_all
  Dir.entries('inputs/').each do |entry|
    next unless entry.end_with?('.zip')

    zip_name = entry.chomp('.zip')
    Zip::File.open("inputs/#{entry}") do |zip_file|
      zip_file.each do |f|
        f_path = File.join("inputs/#{zip_name}", f.name)
        FileUtils.mkdir_p(File.dirname(f_path))
        zip_file.extract(f, f_path) unless File.exist?(f_path)
      end
    end
    FileUtils.rm_rf("inputs/#{entry}") # remove zip file after unzipping
  end
end

################################################
# Reads in all the data in the dockermon csv files
# Files are structured like:
# - inputs/
#   - docker_monitor_report-agent_disabled/
#     - run_0/
#       - metadata.json
#       - output_file.csv
#     - run_1/
#       - metadata.json
#       - output_file.csv
#   - docker_monitor_report-agent_version_1/
#     - run_0/
#       - metadata.json
#       - output_file.csv
#     - run_1/
#       - metadata.json
#       - output_file.csv
################################################
def dockermon_data
  data = {agent_version: []}
  Dir.entries('inputs/').each do |entry|
    next unless entry.start_with?('docker_monitor_report-')

    Dir.entries("inputs/#{entry}").each do |run_iter|
      next unless run_iter.start_with?('run_')

      metadata = {}
      File.open("inputs/#{entry}/#{run_iter}/metadata.json", 'r') do |f|
        metadata = JSON.parse(f.read)
      end
      output_file_name = metadata['output_file_name']
      output_file_name = metadata['output_file'].split('/').last
      agent_version = metadata['agent_version']
      agent_version = 'disabled' if agent_version == 'AGENT_DISABLED'

      read_csv("inputs/#{entry}/#{run_iter}/#{output_file_name}", agent_version, data)
    end
  end
  data
end

def create_graph(data, key)
  Charty.box_plot(data: data, x: :agent_version, y: key).save("output/#{key}.png")
end

def create_network_output_graph(data)
  max = {}

  data[:network_output].each_with_index do |_val, index|
    version = data[:agent_version][index]
    name = data[:"Container Name"][index]
    max[name] ||= {version: version, max: 0}
    max[name][:max] = [max[name][:max], data[:network_output][index]].max
  end

  max_data = {agent_version: [], network_output: []}

  max.each do |key, val|
    max_data[:agent_version] << val[:version]
    max_data[:network_output] << val[:max]
  end

  create_graph(max_data, :network_output)
end

############################################################################################

unzip_all
data = dockermon_data

[:cpu_usage_perc, :cpu_usage, :memory_usage].each do |key|
  puts "key: #{key}, data: [#{data[key].min}, #{data[key].max}]"
  create_graph(data, key)
end

create_network_output_graph(data)

puts '***** COMPLETE *****'
