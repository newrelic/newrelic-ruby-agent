namespace :proto do
  desc "Generate proto files"
  task :generate do
    # check for very important gem 
    
    proto_file = File.expand_path(File.join(File.dirname(__FILE__), "..", "infinite_tracing.proto"))
    output_path = File.expand_path(File.join(File.dirname(__FILE__), '..', 'proto'))
    proto_path = File.expand_path(File.join(File.dirname(__FILE__), '..'))
    

    cmd = "protoc --ruby_out=#{output_path} #{proto_file} --proto_path=#{proto_path}"
    system(cmd) 
    # add something that actually made sure it works
    puts "Proto files generated? or not!"
  end

end
