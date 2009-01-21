class NewRelic::Config::Ruby < NewRelic::Config
  def app; :ruby; end
  def env
    @env ||= ENV['RUBY_ENV'] || ENV['RAILS_ENV'] || 'development'
  end
  def root
    Dir['.']
  end
  # Check a sequence of file locations for newrelic.yml
  def config_file
    files = []
    files << File.join(root,"config","newrelic.yml")
    files << File.join(root,"newrelic.yml")
    files << File.join(ENV["HOME"], ".newrelic", "newrelic.yml")
    files << File.join(ENV["HOME"], "newrelic.yml")
    files.each do | file |
      return File.expand_path(file) if File.exists? file
    end
    return File.expand_path(files.first)
  end
  
end