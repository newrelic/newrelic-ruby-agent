# frozen_string_literal: true

# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: "Star Wars" }, { name: "Lord of the Rings" }])
#   Character.create(name: "Luke", movie: movies.first)

SEED_DATA = <<~SEEDS
  Ruby Agent,newrelic-ruby-agent,Ruby,1145,564
  Python Agent,newrelic-python-agent,Pyhon,109,57
  Java Agent,newrelic-java-agent,Java,112,91
  Node.js Agent,node-newrelic,JavaScript,861,332
  Go Agent,newrelic-client-go,Go,63,64
  .NET Agent,newrelic-dotnet-agent,C#,58,31
  PHP Agent,newrelic-php-agent,C,69,36
  Elixir Agent,elixir_agent,Elixir,229,78
SEEDS

SEED_DATA.split("\n").each do |line|
  name, repository, language, stars, forks = line.split(',')
  Agent.create!(name:, repository:, language:, stars:, forks:)
end
