ENV.keys.each do |k|
  puts "#{k}\t#{ENV[k]}"
end

ENV.keys.map{|k| [k, ENV[k]]}