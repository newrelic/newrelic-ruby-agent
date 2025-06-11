# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module ParsingHelpers
  def parse_operation(operation)
    command = parse_command(operation['command'])
    parameters = parse_parameters(operation['parameters'])

    puts command if ENV['ENABLE_OUTPUT']
    puts parameters if ENV['ENABLE_OUTPUT']

    if operation['childOperations']
      send(command, **parameters) do
        operation['childOperations'].each do |o|
          parse_operation(o)
        end
      end
    else
      send(command, **parameters) do
        parse_assertions(operation['assertions']) if operation['assertions']
      end
    end
  end

  def parse_command(command)
    return 'nr_inject_headers' if command == 'NRInjectHeaders'

    snake_sub_downcase(command).to_sym
  end

  def parse_parameters(parameters)
    return {} unless parameters

    params = parameters.transform_keys { |k| snake_sub_downcase(k).to_sym }

    if params[:span_kind]
      params[:span_kind] = params[:span_kind].downcase.to_sym
    end

    params
  end

  def parse_assertions(assertions)
    assertions.each do |assertion|
      rule = assertion['rule']
      parameters = rule['parameters'].transform_values { |k| snake_sub_downcase(k) }

      puts assertion['description'] if ENV['ENABLE_OUTPUT']
      puts rule if ENV['ENABLE_OUTPUT']

      case rule['operator']
      when 'Equals'
        equals_assertion(parameters)
      when 'NotValid'
        not_valid_assertion(parameters)
      when 'Matches'
        matches_assertion(parameters)
      else
        raise "Missing rule case for assertions! Received: #{rule['operator']}"
      end
    end
  end

  def equals_assertion(parameters)
    left = parameters['left']
    left_result = evaluate_param_for_equals(left)

    right = parameters['right']
    right_result = evaluate_param_for_equals(right)

    assert_equal left_result, right_result, "Expected #{left} to equal #{right}"
  end

  def evaluate_param_for_equals(param)
    puts param if ENV['ENABLE_OUTPUT']

    case param
    when 'current_otel_span.trace_id' then current_otel_span_context&.trace_id
    when 'current_transaction.trace_id' then current_transaction&.trace_id
    when 'current_otel_span.span_id' then current_otel_span_context&.span_id
    when 'current_segment.span_id' then NewRelic::Agent::Tracer.current_segment&.guid
    when 'current_transaction.sampled' then current_transaction&.sampled?
    when 'injected.trace_id' then injected['trace_id']
    when 'injected.span_id' then injected['span_id']
    when 'injected.sampled' then injected['sampled']
    else
      raise "Missing parameter for assertion! Received: #{param}"
    end
  end

  def not_valid_assertion(parameters)
    puts parameters['object'] if ENV['ENABLE_OUTPUT']

    case parameters['object']
    when 'current_otel_span' then current_otel_span
    when 'current_transaction' then current_transaction
    else
      raise "Missing NotValid assertion object! Received: #{parameters['object']}"
    end

    assert_nil eval(parameters['object']), "Expected #{parameters['object']} to be nil"
  end

  def matches_assertion(parameters)
    object = parameters['object']
    actual = case object
    when 'current_otel_span.trace_id' then current_otel_span_context&.trace_id
    else
      raise "Missing object for matches assertion! Received: #{parameters['object']}"
    end

    expected = parameters['value']

    assert_equal expected, actual, "Expected #{object} to equal #{expected}"
  end

  def verify_agent_output(output)
    verify_transaction_output(output['transactions'])
    verify_span_output(output['spans'])
  end

  def verify_transaction_output(output)
    txns = harvest_transaction_events![1].flatten.map { |t| t['name'] }.compact

    assert_equal output.length, txns.length, 'Wrong number of transactions found'

    output.each do |txn|
      assert_includes(txns, txn['name'], "Transaction name #{txn['name']} missing from output")
    end
  end

  def verify_span_output(output)
    # The harvest payload for spans includes some info about the reservoir
    # in the zero-index.
    # The first-index includes the span events that were harvested, which is all
    # we care about for these tests
    spans = harvest_span_events![1]

    output.each do |expected|
      # A harvested span is an array with three hashes:
      # span[0] is the Span event itself
      # span[1] is for custom attributes
      # span[2] is for agent attributes (which aren't tested here)
      actual = spans.find { |s| s[0]['name'] == expected['name'] }

      assert actual, "Span output could not be verified. Span was not found.\n" \
        "Expected: #{expected}\n" \
        "Harvested spans: #{spans}\n"

      if expected['category']
        assert_equal expected['category'], actual[0]['category'], 'Expected category not found.'
      end

      if expected['entryPoint']
        assert_equal expected['entryPoint'], actual[0]['nr.entryPoint'], 'Span was not an entrypoint.'
      end

      expected['attributes']&.each do |expected_key, expected_value|
        assert_equal expected_value, actual[1] & [expected_key],
          "Expected attributes not found.\n" \
          "Expected attribute: {'#{expected_key}' => '#{expected_value}'}\n" \
          "Actual span: #{actual}\n"
      end

      if expected['parentName']
        result = spans.find { |s| s[0]['guid'] == actual[0]['parentId'] } if actual
        result_name = result&.first&.dig('name')

        assert_equal expected['parentName'], result_name,
          "Expected parent name not found.\n" \
          "Expected parent name: #{expected['parentName']}\n" \
          "Actual span: #{actual}\n"
      end
    end
  end

  def snake_sub_downcase(key)
    key.gsub(/(.)([A-Z])/, '\1_\2').downcase
  end
end
