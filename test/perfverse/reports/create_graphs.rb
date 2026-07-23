# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'charty'
require 'zip'
require 'matplotlib'
require 'json'

Charty::Backends.use(:pyplot)
Matplotlib.use(:agg)

CSV_SKIP_LAST = 15
CSV_SKIP_FIRST = 6

# shortens agent_version labels for graph readability -- a long unreleased-branch name is long
# enough to overlap adjacent x-axis tick labels on the box plots
def display_agent_version(agent_version)
  return 'disabled' if agent_version == 'AGENT_DISABLED'
  return agent_version.delete_prefix('BRANCH_') if agent_version.start_with?('BRANCH_')

  agent_version
end

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
#   - docker_monitor_report-iteration_0/
#     - agent_disabled/
#       - metadata.json
#       - output_file.csv
#     - agent_version_1/
#       - metadata.json
#       - output_file.csv
#   - docker_monitor_report-iteration_1/
#     - agent_disabled/
#       - metadata.json
#       - output_file.csv
#     - agent_version_1/
#       - metadata.json
#       - output_file.csv
################################################
def dockermon_data
  data = {agent_version: []}
  Dir.entries('inputs/').each do |entry|
    next unless entry.start_with?('docker_monitor_report-')

    Dir.entries("inputs/#{entry}").each do |tag_dir|
      metadata_path = "inputs/#{entry}/#{tag_dir}/metadata.json"
      next unless File.exist?(metadata_path)

      metadata = JSON.parse(File.read(metadata_path))
      output_file_name = metadata['output_file'].split('/').last
      agent_version = display_agent_version(metadata['agent_version'])

      read_csv("inputs/#{entry}/#{tag_dir}/#{output_file_name}", agent_version, data)
    end
  end
  data
end

def create_graph(data, key, order)
  Charty.box_plot(data: data, x: :agent_version, y: key, order: order).save("output/#{key}.png")
end

def create_network_output_graph(data, order)
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

  create_graph(max_data, :network_output, order)
end

# nil (rather than 0) for percentile columns Locust reports as "N/A" before any request completes
def locust_row_value(raw)
  raw == 'N/A' ? nil : raw.to_f
end

################################################
# Reads in a single locust_stats_history.csv, keeping only the "Aggregated" row per
# timestamp (there's one row per endpoint plus one Aggregated row, with --csv-full-history).
# Timestamps are whole-second unix epoch values sampled once per second, so subtracting
# each run's own first timestamp lines runs with different start times up on a shared
# elapsed-seconds axis without any extra bucketing/rounding.
################################################
def read_locust_stats_history(file_path, agent_version, data)
  start_timestamp = nil

  File.open(file_path, 'r') do |f|
    headers = f.readline.strip.split(',').map(&:strip)

    f.each_line do |line|
      values = line.strip.split(',')
      next if values.length != headers.length

      row = headers.zip(values).to_h
      next unless row['Name'] == 'Aggregated'

      timestamp = row['Timestamp'].to_i
      start_timestamp ||= timestamp

      data[:agent_version] << agent_version
      data[:elapsed_seconds] << (timestamp - start_timestamp)
      data[:requests_per_minute] << row['Requests/s'].to_f * 60
      data[:failures_per_minute] << row['Failures/s'].to_f * 60
      data[:response_time_50th] << locust_row_value(row['50%'])
      data[:response_time_95th] << locust_row_value(row['95%'])
      data[:response_time_99th] << locust_row_value(row['99%'])
      # "Total" columns are cumulative-since-test-start (never "N/A"), unlike the percentile
      # columns above -- Total Max Response Time in particular is a running max, so its graph
      # only ever rises/plateaus rather than tracking a per-second max.
      data[:response_time_avg] << row['Total Average Response Time'].to_f
      data[:response_time_max] << row['Total Max Response Time'].to_f
    end
  end
  data
end

################################################
# Reads in all the locust stats_history csv files
# Files are structured like:
# - inputs/
#   - locust_report-iteration_0/
#     - agent_disabled/
#       - metadata.json
#       - locust_stats_history.csv
#     - agent_version_1/
#       - metadata.json
#       - locust_stats_history.csv
################################################
def locust_data
  data = {
    agent_version: [], elapsed_seconds: [], requests_per_minute: [], failures_per_minute: [],
    response_time_50th: [], response_time_95th: [], response_time_99th: [],
    response_time_avg: [], response_time_max: []
  }

  Dir.entries('inputs/').each do |entry|
    next unless entry.start_with?('locust_report-')

    Dir.entries("inputs/#{entry}").each do |tag_dir|
      metadata_path = "inputs/#{entry}/#{tag_dir}/metadata.json"
      next unless File.exist?(metadata_path)

      metadata = JSON.parse(File.read(metadata_path))
      agent_version = display_agent_version(metadata['agent_version'])

      read_locust_stats_history("inputs/#{entry}/#{tag_dir}/locust_stats_history.csv", agent_version, data)
    end
  end
  data
end

# drops rows where `key` is nil, keeping the remaining columns aligned
def with_present(data, key)
  indices = data[key].each_index.reject { |i| data[key][i].nil? }
  data.transform_values { |values| indices.map { |i| values[i] } }
end

def create_line_graph(data, x, y, color, filename, color_order)
  Charty.line_plot(data: data, x: x, y: y, color: color, color_order: color_order).save("output/#{filename}.png")
end

# fixes agent_version -> color/x-position mapping across every graph -- without this, each
# graph independently infers category order from Dir.entries/row order (neither of which is
# guaranteed consistent between dockermon and locust data, or even between two runs of the
# same graph), so the same version could end up a different color on every chart
def agent_version_order(*datasets)
  datasets.flat_map { |d| d[:agent_version] }.uniq.sort
end

############################################################################################

unzip_all
data = dockermon_data
locust = locust_data
order = agent_version_order(data, locust)

[:cpu_usage_perc, :cpu_usage, :memory_usage].each do |key|
  puts "key: #{key}, data: [#{data[key].min}, #{data[key].max}]"
  create_graph(data, key, order)
end

create_network_output_graph(data, order)

create_line_graph(locust, :elapsed_seconds, :requests_per_minute, :agent_version, 'requests_per_minute', order)
create_line_graph(locust, :elapsed_seconds, :failures_per_minute, :agent_version, 'failures_per_minute', order)
create_line_graph(locust, :elapsed_seconds, :response_time_avg, :agent_version, 'response_time_avg_ms', order)
create_line_graph(locust, :elapsed_seconds, :response_time_max, :agent_version, 'response_time_max_ms', order)

# separate charts per percentile rather than one combined chart -- :color is already used for
# agent_version, and overlaying percentile as a second grouping made it unreadable
[:response_time_50th, :response_time_95th, :response_time_99th].each do |key|
  filtered = with_present(locust, key)
  create_line_graph(filtered, :elapsed_seconds, key, :agent_version, "#{key}_ms", order)
end

# box-plot summary (pooling every sample across the run, same convention as the cpu/memory
# box plots above) of p95 latency per version, for an at-a-glance "which version is slower"
create_graph(with_present(locust, :response_time_95th), :response_time_95th, order)

puts '***** COMPLETE *****'
