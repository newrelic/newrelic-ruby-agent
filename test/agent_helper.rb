# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# These helpers should not have any gem dependencies except on newrelic_rpm
# itself, and should be usable from within any multiverse suite.

class ArrayLogDevice
  def initialize( array=[] )
    @array = array
  end
  attr_reader :array

  def write( message )
    @array << message
  end

  def close; end
end

def assert_between(floor, ceiling, value, message="expected #{floor} <= #{value} <= #{ceiling}")
  assert((floor <= value && value <= ceiling), message)
end

def assert_in_delta(expected, actual, delta)
  assert_between((expected - delta), (expected + delta), actual)
end

def assert_has_error(error_class)
  assert \
    NewRelic::Agent.instance.error_collector.errors.find {|e| e.exception_class_name == error_class.name} != nil, \
    "Didn't find error of class #{error_class}"
end

unless defined?( assert_block )
  def assert_block(*msgs)
    assert yield, *msgs
  end
end

unless defined?( assert_includes )
  def assert_includes( collection, member, msg=nil )
    msg = "Expected #{collection.inspect} to include #{member.inspect}"
    assert_block( msg ) { collection.include?(member) }
  end
end

unless defined?( assert_not_includes )
  def assert_not_includes( collection, member, msg=nil )
    msg = "Expected #{collection.inspect} not to include #{member.inspect}"
    assert !collection.include?(member), msg
  end
end

unless defined?( assert_empty )
  def assert_empty(collection, msg=nil)
    assert collection.empty?, msg
  end
end

def assert_equal_unordered(left, right)
  assert_equal(left.length, right.length, "Lengths don't match. #{left.length} != #{right.length}")
  left.each { |element| assert_includes(right, element) }
end

def compare_metrics(expected, actual)
  actual.delete_if {|a| a.include?('GC/Transaction/') }
  assert_equal(expected.to_a.sort, actual.to_a.sort, "extra: #{(actual - expected).to_a.inspect}; missing: #{(expected - actual).to_a.inspect}")
end

def metric_spec_from_specish(specish)
  spec = case specish
  when String then NewRelic::MetricSpec.new(specish)
  when Array  then NewRelic::MetricSpec.new(*specish)
  end
  spec
end

def _normalize_metric_expectations(expectations)
  case expectations
  when Array
    hash = {}
    # Just assert that the metric is present, nothing about the attributes
    expectations.each { |k| hash[k] = { } }
    hash
  when String
    { expectations => {} }
  else
    expectations
  end
end

def dump_stats(stats)
  str =  "  Call count:           #{stats.call_count}\n"
  str << "  Total call time:      #{stats.total_call_time}\n"
  str << "  Total exclusive time: #{stats.total_exclusive_time}\n"
  str << "  Min call time:        #{stats.min_call_time}\n"
  str << "  Max call time:        #{stats.max_call_time}\n"
  str << "  Sum of squares:       #{stats.sum_of_squares}\n"
  str << "  Apdex S:              #{stats.apdex_s}\n"
  str << "  Apdex T:              #{stats.apdex_t}\n"
  str << "  Apdex F:              #{stats.apdex_f}\n"
  str
end

def assert_stats_has_values(stats, expected_spec, expected_attrs)
  expected_attrs.each do |attr, expected_value|
    actual_value = stats.send(attr)
    if attr == :call_count
      assert_equal(expected_value, actual_value,
        "Expected #{attr} for #{expected_spec} to be #{expected_value}, got #{actual_value}.\nActual stats:\n#{dump_stats(stats)}")
    else
      assert_in_delta(expected_value, actual_value, 0.0001,
        "Expected #{attr} for #{expected_spec} to be ~#{expected_value}, got #{actual_value}.\nActual stats:\n#{dump_stats(stats)}")
    end
  end
end

def assert_metrics_recorded(expected)
  expected = _normalize_metric_expectations(expected)
  expected.each do |specish, expected_attrs|
    expected_spec = metric_spec_from_specish(specish)
    actual_stats = NewRelic::Agent.instance.stats_engine.lookup_stats(*Array(specish))
    if !actual_stats
      all_specs = NewRelic::Agent.instance.stats_engine.metric_specs.sort
      matches = all_specs.select { |spec| spec.name == expected_spec.name }
      matches.map! { |m| "  #{m.inspect}" }

      msg = "Did not find stats for spec #{expected_spec.inspect}."
      msg += "\nDid find specs: [\n#{matches.join(",\n")}\n]" unless matches.empty?
      msg += "\nAll specs in there were: #{format_metric_spec_list(all_specs)}"

      assert(actual_stats, msg)
    end
    assert_stats_has_values(actual_stats, expected_spec, expected_attrs)
  end
end

# Use this to assert that *only* the given set of metrics has been recorded.
#
# If you want to scope the search for unexpected metrics to a particular
# namespace (e.g. metrics matching 'Controller/'), pass a Regex for the
# :filter option. Only metrics matching the regex will be searched when looking
# for unexpected metrics.
#
# If you want to *allow* unexpected metrics matching certain patterns, use
# the :ignore_filter option. This will allow you to specify a Regex that
# whitelists broad swathes of metric territory (e.g. 'Supportability/').
#
def assert_metrics_recorded_exclusive(expected, options={})
  expected = _normalize_metric_expectations(expected)
  assert_metrics_recorded(expected)

  recorded_metrics = NewRelic::Agent.instance.stats_engine.metric_specs

  if options[:filter]
    recorded_metrics = recorded_metrics.select { |m| m.name.match(options[:filter]) }
  end
  if options[:ignore_filter]
    recorded_metrics.reject! { |m| m.name.match(options[:ignore_filter]) }
  end

  expected_metrics   = expected.keys.map { |s| metric_spec_from_specish(s) }

  unexpected_metrics = recorded_metrics - expected_metrics
  unexpected_metrics.reject! { |m| m.name =~ /GC\/Transaction/ }

  assert_equal(0, unexpected_metrics.size, "Found unexpected metrics: #{format_metric_spec_list(unexpected_metrics)}")
end

def assert_metrics_not_recorded(not_expected)
  not_expected = _normalize_metric_expectations(not_expected)
  found_but_not_expected = []
  not_expected.each do |specish, _|
    spec = metric_spec_from_specish(specish)
    if NewRelic::Agent.instance.stats_engine.lookup_stats(*Array(specish))
      found_but_not_expected << spec
    end
  end
  assert_equal([], found_but_not_expected, "Found unexpected metrics: #{format_metric_spec_list(found_but_not_expected)}")
end

def format_metric_spec_list(specs)
  spec_strings = specs.map do |spec|
    "#{spec.name} (#{spec.scope.empty? ? '<unscoped>' : spec.scope})"
  end
  "[\n  #{spec_strings.join(",\n  ")}\n]"
end

def assert_truthy(expected, msg = nil)
  msg = "Expected #{expected.inspect} to be truthy"
  assert !!expected, msg
end

def assert_falsy(expected, msg = nil)
  msg = "Expected #{expected.inspect} to be falsy"
  assert !expected, msg
end

unless defined?( assert_false )
  def assert_false(expected)
    assert_equal false, expected
  end
end

unless defined?(refute)
  alias refute assert_false
end

# Mock up a transaction for testing purposes, optionally specifying a name and
# transaction category. The given block will be executed within the context of the
# dummy transaction.
#
# Examples:
#
# With default name ('dummy') and category (:other):
#   in_transaction { ... }
#
# With an explicit transaction name and default category:
#   in_transaction('foobar') { ... }
#
# With default name and explicit category:
#   in_transaction(:category => :controller) { ... }
#
# With a transaction name plus category:
#   in_transaction('foobar', :category => :controller) { ... }
#
def in_transaction(*args)
  opts = (args.last && args.last.is_a?(Hash)) ? args.pop : {}
  opts[:transaction_name] = args.first || 'dummy'
  category = (opts && opts.delete(:category)) || :other
  state = NewRelic::Agent::TransactionState.tl_get

  NewRelic::Agent::Transaction.start(state, category, opts)

  val = nil

  begin
    val = yield state.current_transaction
  ensure
    NewRelic::Agent::Transaction.stop(state)
  end

  val
end

# Convenience wrapper around in_transaction that sets the category so that it
# looks like we are in a web transaction
def in_web_transaction(name='dummy')
  in_transaction(name, :category => :controller) do
    yield
  end
end

def find_last_transaction_segment(transaction_sample=nil)
  if transaction_sample
    root_segment = transaction_sample.root_segment
  else
    builder = NewRelic::Agent.agent.transaction_sampler.tl_builder
    root_segment = builder.current_segment
  end

  last_segment = nil
  root_segment.each_segment {|s| last_segment = s }

  return last_segment
end

def collect_segment_names(transaction_sample)
  names = []

  transaction_sample.root_segment.each_segment do |segment|
    names << segment.metric_name
  end

  names
end

def find_segment_with_name(transaction_sample, name)
  transaction_sample.root_segment.each_segment do |segment|
    if segment.metric_name == name
      return segment
    end
  end

  nil
end

def find_segment_with_name_matching(transaction_sample, regex)
  transaction_sample.root_segment.each_segment do |segment|
    if segment.metric_name.match regex
      return segment
    end
  end

  nil
end

def find_all_segments_with_name_matching(transaction_sample, regexes)
  regexes = [regexes].flatten
  matching_segments = []

  transaction_sample.root_segment.each_segment do |segment|
    regexes.each do |regex|
      if segment.metric_name.match regex
        matching_segments << segment
      end
    end
  end

  matching_segments
end

def with_config(config_hash, opts={})
  opts = { :level => 0, :do_not_cast => false }.merge(opts)
  if opts[:do_not_cast]
    config = config_hash
  else
    config = NewRelic::Agent::Configuration::DottedHash.new(config_hash)
  end
  NewRelic::Agent.config.add_config_for_testing(config, opts[:level])
  begin
    yield
  ensure
    NewRelic::Agent.config.remove_config(config)
  end
end

def freeze_time(now=Time.now)
  Time.stubs(:now).returns(now)
  now
end

def advance_time(seconds)
  freeze_time(Time.now + seconds)
end

def with_constant_defined(constant_symbol, implementation)
  const_path = constant_path(constant_symbol.to_s)

  if const_path
    # Constant is already defined, nothing to do
    return yield
  else
    const_path = constant_path(constant_symbol.to_s, :allow_partial => true)
    parent = const_path[-1]
    constant_symbol = constant_symbol.to_s.split('::').last.to_sym
  end

  begin
    parent.const_set(constant_symbol, implementation)
    yield
  ensure
    parent.send(:remove_const, constant_symbol)
  end
end

def constant_path(name, opts={})
  allow_partial = opts[:allow_partial]
  path = [Object]
  parts = name.gsub(/^::/, '').split('::')
  parts.each do |part|
    if !path.last.const_defined?(part)
      return allow_partial ? path : nil
    end
    path << path.last.const_get(part)
  end
  path
end

def undefine_constant(constant_symbol)
  const_path = constant_path(constant_symbol.to_s)
  return yield unless const_path
  parent = const_path[-2]
  const_name = constant_symbol.to_s.gsub(/.*::/, '')
  removed_constant = parent.send(:remove_const, const_name)
  yield
ensure
  parent.const_set(const_name, removed_constant) if removed_constant
end

def with_debug_logging
  orig_logger = NewRelic::Agent.logger
  $stderr.puts '', '---', ''
  NewRelic::Agent.logger =
    NewRelic::Agent::AgentLogger.new('', Logger.new($stderr) )

  with_config(:log_level => 'debug') do
    yield
  end
ensure
  NewRelic::Agent.logger = orig_logger
end

def create_agent_command(args = {})
  NewRelic::Agent::Commands::AgentCommand.new([-1, { "name" => "command_name", "arguments" => args}])
end

def wait_for_backtrace_service_poll(opts={})
  defaults = {
    :timeout => 10.0,
    :service => NewRelic::Agent.agent.agent_command_router.backtrace_service,
    :iterations => 1
  }
  opts = defaults.merge(opts)
  deadline = Time.now + opts[:timeout]
  until opts[:service].worker_loop.iterations > opts[:iterations]
    sleep(0.01)
    if Time.now > deadline
      raise "Timed out waiting #{opts[:timeout]} s for backtrace service poll"
    end
  end
end

def with_array_logger(level=:info)
  orig_logger = NewRelic::Agent.logger
  config = {
      :log_file_path => nil,
      :log_file_name => nil,
      :log_level => level,
    }
  logdev = ArrayLogDevice.new
  override_logger = Logger.new(logdev)

  with_config(config) do
    NewRelic::Agent.logger = NewRelic::Agent::AgentLogger.new("", override_logger)
    yield
  end

  return logdev
ensure
  NewRelic::Agent.logger = orig_logger
end

def with_environment(env)
  old_env = {}
  env.each do |key, val|
    old_env[key] = ENV[key]
    ENV[key]     = val.to_s
  end
  begin
    yield
  ensure
    old_env.each { |key, old_val| ENV[key] = old_val }
  end
end

def with_ignore_error_filter(filter, &blk)
  original_filter = NewRelic::Agent.ignore_error_filter
  NewRelic::Agent.ignore_error_filter(&filter)

  yield
ensure
  if original_filter.nil?
    NewRelic::Agent.instance.error_collector.clear_ignore_error_filter
  else
    NewRelic::Agent.ignore_error_filter(&original_filter)
  end
end
