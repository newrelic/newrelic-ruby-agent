namespace :proto do
  desc "Generate proto files"
  task :generate do
    proto_file = File.expand_path(File.join(File.dirname(__FILE__), "..", "infinite_tracing.proto"))
    output_path = File.expand_path(File.join(File.dirname(__FILE__), '..', 'proto'))
    proto_path = File.expand_path(File.join(File.dirname(__FILE__), '..'))

    cmd = "grpc_tools_ruby_protoc -I #{proto_path} --ruby_out=#{output_path} --grpc_out=#{output_path} #{proto_file}"
    success = system(cmd)

    if success
      puts "Proto file generated!"
    else
      puts "Failed to create proto file."
    end
  end

end
