class NewRelic::Config::Ruby < NewRelic::Config
  def app; :ruby; end
  def env
    ENV['RUBY_ENV'] || 'development'
  end
  def root
    Dir['.']
  end
end