# run unit tests for the NewRelic Agent
namespace :newrelic do
  desc "Install a default config/newrelic.yml file"
  task :install do
    load File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "install.rb"))
  end

  namespace :config do
    desc "Describe available New Relic configuration settings."

    def output_text
      NewRelic::Agent::Configuration::DEFAULTS.each do |key, value|
        if value[:public]
          puts "Setting:      #{key}"
          if value[:type] == NewRelic::Agent::Configuration::Boolean
            puts "Type:         Boolean"
          else
            puts "Type:         #{value[:type]}"
          end
          puts "Default:      #{format_default_value(value)}"

          puts 'Description:  ' + value[:description]
          puts "-" * (value[:description].length + 14)
        end
      end
    end

    def format_default_value(spec)
      if spec[:default].is_a?(Proc)
        '(Dynamic)'
      else
        spec[:default].inspect
      end
    end

    def output_html
      puts "<table>"
      puts "<thead>"
      puts "  <th>Setting</th>"
      puts "  <th style='width: 15%'>Type</th>"
      puts "  <th>Description</th>"
      puts "</thead>"

      NewRelic::Agent::Configuration::DEFAULTS.each do |key, value|
        if value[:public]
          puts "<tr>"
          puts "  <td><a name='#{key}'></a>#{key}</td>"
          puts "  <td>#{value[:type].to_s.gsub("NewRelic::Agent::Configuration::", "")}</td>"
          puts "  <td>#{format_default_value(value)}</td>"
          puts "  <td>#{value[:description]}</td>"
          puts "</tr>"
        end
      end

      puts "</table>"
    end

    task :docs, [:format] => [] do |t, args|
      require File.expand_path(File.join(File.dirname(__FILE__), "..", "new_relic", "agent", "configuration", "default_source.rb"))

      format = args[:format]
      if format.nil? || format == "text"
        output_text
      else
        output_html
      end
    end
  end
end
