# frozen_string_literal: true

require 'json'

def output_line(str)
  puts "*" * 120
  puts str
end

def run_command(command)
  puts "Running command: #{command}"
  `#{command}`
end

def transform_agent_tags(agent_tag)
  agent_tag.split(':', 2).tap do |array|
    array[1] = array[1]&.split(';')
  end
end

def build_rails_app(git_tag)
  output_line("Building rails app with git tag #{git_tag}")
  run_command("cd ./test/perfverse/ && docker build --pull --build-arg AGENT_VERSION=#{git_tag} --progress=plain -t ruby_perf_app:local .")
end

def build_docker_monitor_report
  output_line("Building docker monitor image")
  run_command('cd ./test/perfverse/docker_monitor && docker build --pull --progress=plain -t docker_monitor_report:local . ')
end

def pull_locust
  output_line("Pulling locust docker image")
  run_command("docker pull locustio/locust")
end

def generate_otlp_cert
  output_line("Generating local otlp_receiver cert")
  run_command('./test/perfverse/bin/generate-otlp-cert.sh')
end

def ensure_network
  output_line("Ensuring perfverse_net Docker network exists")
  run_command('docker network create perfverse_net 2>/dev/null || true')
end

def build_otlp_receiver
  output_line("Building otlp_receiver image")
  run_command('docker build --pull --progress=plain -f test/perfverse/otlp_receiver/Dockerfile -t otlp_receiver:local .')
end

def run_otlp_receiver
  output_line("Starting otlp_receiver sidecar")
  # Container name doubles as its DNS name on perfverse_net -- must be hyphenated since
  # URI::HTTPS.build rejects underscores as an invalid host component.
  run_command('docker run -d --rm --name otlp-receiver --network perfverse_net otlp_receiver:local')
end

# Both the app and otlp-receiver containers run with --rm, so their logs vanish the moment
# `docker stop` returns -- this must run on the still-running container, before it's stopped.
def print_container_logs(container_id, grep_pattern)
  output_line("#{container_id} logs (filtered: #{grep_pattern}):")
  matched = run_command("docker logs #{container_id} 2>&1 | grep -iE \"#{grep_pattern}\"")
  puts matched.empty? ? '(no matching log lines found)' : matched
end

def stop_otlp_receiver
  print_container_logs('otlp-receiver', 'Received export|Failed to decode')
  output_line("Stopping otlp_receiver sidecar")
  run_command('docker stop otlp-receiver')
end

def shutdown_rails_app(container_id)
  print_container_logs(container_id, 'continuous profil|stackprof|export')
  output_line("Shutting down rails app")
  run_command("docker stop #{container_id}")
end

def run_traffic(agent_tag, iteration)
  output_dir = "output/run_#{iteration}"
  output_line("Running locust traffic with #{ENV['RUN_TIME']} duration")
  # locustio/locust runs as a non-root uid inside the container, so the bind-mounted
  # output dir (created here as whatever uid the runner is) needs to be world-writable
  # or Locust fails to open its --csv files and exits immediately.
  run_command("mkdir -p ./test/perfverse/traffic/#{output_dir} && chmod 777 ./test/perfverse/traffic/#{output_dir}")
  run_command("cd ./test/perfverse/traffic && docker run -p 8089:8089 --network=\"host\" -v $PWD:/mnt/locust locustio/locust -t $RUN_TIME -f /mnt/locust/driver.py --host=http://127.0.0.1:3000 --headless -u 5 --csv=/mnt/locust/#{output_dir}/locust --csv-full-history")
  File.write("./test/perfverse/traffic/#{output_dir}/metadata.json", {agent_version: agent_tag}.to_json)
end

def run_rails_app(agent_tag, env_vars, iteration)
  env_str = ''
  env_vars&.each do |env_var|
    env_str += "-e #{env_var} "
  end

  app_name = "ruby_perf_app_#{ENV['TEST_TAG']}_#{agent_tag}_#{iteration}"
  output_line("Running ruby app in background. Name: #{app_name}")
  cpu_mem = '--cpus 4 --memory 2G'

  Thread.new do
    run_command("cd ./test/perfverse/ && docker run --rm --name #{app_name} --network perfverse_net #{cpu_mem} #{env_str} -e NEW_RELIC_LICENSE_KEY=$NR_LICENSE_KEY -e NEW_RELIC_APP_NAME=#{app_name} -e NEW_RELIC_HOST=staging-collector.newrelic.com -e s -p 3000:3000 ruby_perf_app:local")
  end
  sleep 2
  thread = run_docker_report(agent_tag, app_name, iteration)
  sleep 1

  [app_name, thread]
end

def run_docker_report(agent_tag, container_ids, iteration)
  Thread.new do
    output_dir = "#{ENV['DOCKER_MONITOR_OUTPUT_DIR']}/run_#{iteration}"
    env_str = ''
    env_str += "-e TEST_TAG=#{ENV['TEST_TAG']} "
    env_str += "-e AGENT_VERSION=#{agent_tag} "
    env_str += "-e DOCKER_MONITOR_OUTPUT_DIR=#{output_dir} "
    env_str += "-e MONITOR_CONTAINERS=#{container_ids} "

    docker_mount_bind = "--mount type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock"
    output_mount_bind = "--mount type=bind,source=./#{output_dir},target=/app/#{output_dir}"

    command = "cd ./test/perfverse/docker_monitor && mkdir -p #{output_dir} && "
    command << "sudo docker run --rm --name docker_monitor_report #{env_str} #{docker_mount_bind} #{output_mount_bind} docker_monitor_report:local"

    output_line("Running docker monitor report")
    output = run_command(command)

    output_line("Docker Monitor Report Output: \n" + output)
  end
end

###############################################################################

iterations = ENV['ITERATIONS'].to_i
agent_tag, env_vars = transform_agent_tags(ENV['AGENT_TAG'])
output_line("Running perf test #{iterations} times for #{ENV['RUN_TIME']} with agent tag #{agent_tag} and env vars #{env_vars}")

generate_otlp_cert
ensure_network
pull_locust
build_docker_monitor_report
build_otlp_receiver
run_otlp_receiver

iterations.times do |i|
  build_rails_app(agent_tag)

  app_name, monitor_thread = run_rails_app(agent_tag, env_vars, i)
  run_traffic(agent_tag, i)

  shutdown_rails_app(app_name)
  monitor_thread.join
end

stop_otlp_receiver

