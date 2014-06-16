namespace :newrelic do
  desc "Lists information on supported versions of frameworks for this agent"

  require File.join(File.dirname(__FILE__), '..', 'new_relic', 'agent', 'supported_versions')

  task :supported_versions, [:format] => [] do |t, args|

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

    VersionStruct = Struct.new(:name, :supported, :deprecated, :experimental, :notes)

    format = args[:format] || "txt"
    erb = build_erb(format)

    write_versions("Ruby Versions",   :ruby, erb)
    write_versions("Web Servers",     :app_server, erb)
    write_versions("Web Frameworks",  :web, erb)
    write_versions("Database",        :database, erb)
    write_versions("Background Jobs", :background, erb)
    write_versions("HTTP Clients",    :http, erb)
    write_versions("Other",           :other, erb)
  end
end
