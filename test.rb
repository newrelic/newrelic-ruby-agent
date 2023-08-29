# frozen_string_literal: true

string = 'hello string'
array = %w[hello array]
symbol = :hello_symbol
regexp = /hello regex/

[string, array, symbol, regexp].each { |o| puts "#{o} (#{o.class}) frozen? => #{o.frozen?}" }
