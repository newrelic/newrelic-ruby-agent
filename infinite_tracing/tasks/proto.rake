namespace :proto do
  desc "Generate proto files"
  task :generate do
    proto_file = File.expand_path(File.join(File.dirname(__FILE__), "..", "infinite_tracing.proto"))
    output_path = File.expand_path(File.join(File.dirname(__FILE__), '..', 'proto'))
    proto_path = File.expand_path(File.join(File.dirname(__FILE__), '..'))

    cmd = "protoc --ruby_out=#{output_path} #{proto_file} --proto_path=#{proto_path}"
    success = system(cmd)

    if success
      puts "Proto file generated!"
    else
      puts "Failed to create proto file."
    end
  end

end
