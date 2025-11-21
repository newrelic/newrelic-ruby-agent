#!/usr/bin/env ruby
# frozen_string_literal: true

# Performance benchmark comparing old vs new implementations
# Run with: ruby benchmark_performance_improvements.rb

require 'benchmark'
require 'set'

puts "Ruby Version: #{RUBY_VERSION}"
puts "=" * 80
puts

# ==============================================================================
# Benchmark 1: add_new_segment_attributes - Array vs Set lookups
# ==============================================================================

puts "Benchmark 1: Array#include? (O(n)) vs Set#include? (O(1))"
puts "-" * 80

# Simulate segment attributes
existing_keys_small = (1..10).map { |i| "key_#{i}".to_sym }
existing_keys_large = (1..100).map { |i| "key_#{i}".to_sym }

# Simulate params to check
params_to_check = (1..50).map { |i| ["param_#{i}".to_sym, "value_#{i}"] }.to_h

def old_implementation_array(params, existing_keys_array)
  params.reject do |k, _v|
    existing_keys_array.include?(k.to_sym) if k.respond_to?(:to_sym)
  end
end

def new_implementation_set(params, existing_keys_set)
  params.reject do |k, _v|
    k.respond_to?(:to_sym) && existing_keys_set.include?(k.to_sym)
  end
end

puts "\nWith 10 existing keys:"
Benchmark.bmbm(25) do |x|
  x.report("OLD: Array#include?") do
    10_000.times { old_implementation_array(params_to_check, existing_keys_small) }
  end

  x.report("NEW: Set#include?") do
    existing_set = Set.new(existing_keys_small)
    10_000.times { new_implementation_set(params_to_check, existing_set) }
  end
end

puts "\nWith 100 existing keys (shows O(n) vs O(1) difference):"
Benchmark.bmbm(25) do |x|
  x.report("OLD: Array#include?") do
    10_000.times { old_implementation_array(params_to_check, existing_keys_large) }
  end

  x.report("NEW: Set#include?") do
    existing_set = Set.new(existing_keys_large)
    10_000.times { new_implementation_set(params_to_check, existing_set) }
  end
end

# ==============================================================================
# Benchmark 2: get_transaction_name - Regexp vs delete_prefix
# ==============================================================================

puts "\n\n"
puts "Benchmark 2: Regexp.new + sub vs String#delete_prefix"
puts "-" * 80

transaction_name = "Controller/MyApp/UsersController/index"
prefix = "Controller/"

def old_implementation_regexp(name, prefix)
  name.sub(Regexp.new("\\A#{Regexp.escape(prefix)}"), '')
end

def new_implementation_delete_prefix(name, prefix)
  name.delete_prefix(prefix)
end

puts "\nRemoving prefix from transaction name:"
Benchmark.bmbm(25) do |x|
  x.report("OLD: Regexp.new + sub") do
    100_000.times { old_implementation_regexp(transaction_name, prefix) }
  end

  x.report("NEW: delete_prefix") do
    100_000.times { new_implementation_delete_prefix(transaction_name, prefix) }
  end
end

# ==============================================================================
# Benchmark 3: Hash.new vs {}
# ==============================================================================

puts "\n\n"
puts "Benchmark 3: Hash.new vs {}"
puts "-" * 80

Benchmark.bmbm(25) do |x|
  x.report("OLD: Hash.new") do
    1_000_000.times { Hash.new }
  end

  x.report("NEW: {}") do
    1_000_000.times { {} }
  end
end

# ==============================================================================
# Benchmark 4: record_metric_once - Memory usage comparison
# ==============================================================================

puts "\n\n"
puts "Benchmark 4: Memory leak prevention in record_metric_once"
puts "-" * 80
puts "(Simulating unbounded Set vs bounded Set with 10k limit)"

def old_implementation_unbounded(metric_names)
  metrics_recorded = Set.new
  metric_names.each do |name|
    metrics_recorded.add(name)
  end
  metrics_recorded.size
end

def new_implementation_bounded(metric_names, max_size = 10_000)
  metrics_recorded = Set.new
  metric_names.each do |name|
    # Clear if too large
    metrics_recorded.clear if metrics_recorded.size >= max_size
    metrics_recorded.add(name)
  end
  metrics_recorded.size
end

# Generate 50k unique metric names
large_metric_set = (1..50_000).map { |i| "Custom/Metric/#{i}" }

puts "\nProcessing 50,000 unique metrics:"

result_old = nil
result_new = nil

Benchmark.bmbm(25) do |x|
  x.report("OLD: Unbounded Set") do
    result_old = old_implementation_unbounded(large_metric_set)
  end

  x.report("NEW: Bounded Set (10k)") do
    result_new = new_implementation_bounded(large_metric_set, 10_000)
  end
end

puts "\n  OLD Set final size: #{result_old} (memory leak!)"
puts "  NEW Set final size: #{result_new} (bounded to prevent leaks)"

# ==============================================================================
# Summary
# ==============================================================================

puts "\n\n"
puts "=" * 80
puts "SUMMARY"
puts "=" * 80
puts
puts "1. Array vs Set lookups:"
puts "   - Set is O(1) vs Array's O(n), providing significant speedup"
puts "   - Performance gap widens as the number of existing keys increases"
puts
puts "2. Regexp vs delete_prefix:"
puts "   - delete_prefix avoids regexp compilation overhead"
puts "   - Expected 5-10x faster for simple prefix removal"
puts
puts "3. Hash.new vs {}:"
puts "   - {} is marginally faster (avoids method call)"
puts "   - Minor optimization but adds up in hot code paths"
puts
puts "4. Bounded Set for record_metric_once:"
puts "   - Prevents unbounded memory growth in long-running processes"
puts "   - Slight performance overhead but critical for stability"
puts "=" * 80
