path = File.expand_path('../vendor/gems/dependency_detection/lib', File.dirname(__FILE__))
puts path.inspect
$LOAD_PATH << path
require 'dependency_detection'
