namespace :newrelic do
  desc "Lists information on supported versions of frameworks for this agent"

  require File.join(File.dirname(__FILE__), '..', 'new_relic', 'agent', 'supported_versions')

  task :supported_versions, [:format] => [] do |t, args|
    require 'cgi'

    def version_list(list)
      return "-" if list.nil? || list.empty?
      list.join(", ")
    end

    def versions_for_type(type)
      NewRelic::Agent::SUPPORTED_VERSIONS.
        select  {|key, values| values[:type] == type}.
        sort_by {|key, values| (values[:name] || key).to_s }.
        map    do |key,values|
          VersionStruct.new(
            values[:name] || key,
            values[:supported],
            values[:deprecated],
            values[:experimental],
            values[:notes])
        end
    end

    def build_erb(format)
      require 'erb'
      path = File.join(File.dirname(__FILE__), "versions.#{format}.erb")
      template = File.read(File.expand_path(path))
      ERB.new(template)
    end

    def write_versions(title, type, erb)
      anchor = title.downcase.gsub(" ", "_")
      versions = versions_for_type(type)
      puts erb.result(binding).gsub(/^ *$/, '')
    end

    def include_if_exists(filename)
      path = File.join(File.dirname(__FILE__), filename)
      puts File.read(path) if File.exists?(path)
    end

    VersionStruct = Struct.new(:name, :supported, :deprecated, :experimental, :notes)

    format = args[:format] || "txt"
    erb = build_erb(format)

    include_if_exists("versions.preface.#{format}")

    write_versions("Ruby versions",   :ruby, erb)
    write_versions("Web servers",     :app_server, erb)
    write_versions("Web frameworks",  :web, erb)
    write_versions("Databases",       :database, erb)
    write_versions("Background jobs", :background, erb)
    write_versions("HTTP clients",    :http, erb)
    write_versions("Other",           :other, erb)

    include_if_exists("versions.postface.#{format}")
  end
end
