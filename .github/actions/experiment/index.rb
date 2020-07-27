ENV.keys.each do |k|
  puts "#{k}\t#{ENV[k]}"
end

ENV["OUTPUT_OUTPUT"] = ENV.keys.map{|k| [k, ENV[k]]}.join("\n")