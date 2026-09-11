# frozen_string_literal: true

require 'json'

def output_line(str)
  puts '*' * 120
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

def sanitize_tag(tag)
  tag.gsub(/[^\w.-]/, '_')
end

def build_rails_app(git_tag)
  output_line("Building rails app with git tag #{git_tag}")
  run_command("cd ./test/perfverse/ && docker build --pull --build-arg AGENT_VERSION=#{git_tag} --progress=plain -t ruby_perf_app:local .")
end

def build_docker_monitor_report
  output_line('Building docker monitor image')
  run_command('cd ./test/perfverse/docker_monitor && docker build --pull --progress=plain -t docker_monitor_report:local . ')
end

def pull_locust
  output_line('Pulling locust docker image')
  run_command('docker pull locustio/locust')
end

# The app container runs with --rm, so its logs vanish the moment `docker stop` returns --
# this must run on the still-running container, before it's stopped.
def print_container_logs(container_id, grep_pattern)
  output_line("#{container_id} logs (filtered: #{grep_pattern}):")
  matched = run_command("docker logs #{container_id} 2>&1 | grep -iE \"#{grep_pattern}\"")
  puts matched.empty? ? '(no matching log lines found)' : matched
end

def shutdown_rails_app(container_id)
  print_container_logs(container_id, 'continuous profil|stackprof|export')
  output_line('Shutting down rails app')
  run_command("docker stop #{container_id}")
end

def run_traffic(agent_tag)
  output_dir = "output/#{sanitize_tag(agent_tag)}"
  output_line("Running locust traffic with #{ENV['RUN_TIME']} duration")
  # locustio/locust runs as a non-root uid inside the container, so the bind-mounted
  # output dir (created here as whatever uid the runner is) needs to be world-writable
  # or Locust fails to open its --csv files and exits immediately.
  run_command("mkdir -p ./test/perfverse/traffic/#{output_dir} && chmod 777 ./test/perfverse/traffic/#{output_dir}")
  run_command("cd ./test/perfverse/traffic && docker run -p 8089:8089 --network=\"host\" -v $PWD:/mnt/locust locustio/locust -t $RUN_TIME -f /mnt/locust/driver.py --host=http://127.0.0.1:3000 --headless -u 5 --csv=/mnt/locust/#{output_dir}/locust --csv-full-history")
  File.write("./test/perfverse/traffic/#{output_dir}/metadata.json", {agent_version: agent_tag}.to_json)
end

def run_rails_app(agent_tag, env_vars)
  env_str = ''
  env_vars&.each do |env_var|
    env_str += "-e #{env_var} "
  end

  app_name = "ruby_perf_app_#{ENV['TEST_TAG']}_#{sanitize_tag(agent_tag)}"
  output_line("Running ruby app in background. Name: #{app_name}")
  # runs-on: ubuntu-latest is a 2 vCPU host -- --cpus 4 was asking for more cores than the
  # box has, so the app was already contending with Locust/docker_monitor/the OS for the
  # same 2 real cores no matter what limit was set here. 1.5 leaves real headroom for those.
  cpu_mem = '--cpus 1.5 --memory 2G'

  Thread.new do
    run_command("cd ./test/perfverse/ && docker run --rm --name #{app_name} #{cpu_mem} #{env_str} -e NEW_RELIC_LICENSE_KEY=$NR_LICENSE_KEY -e NEW_RELIC_APP_NAME=#{app_name} -e NEW_RELIC_HOST=staging-collector.newrelic.com -e s -p 3000:3000 ruby_perf_app:local")
  end
  sleep 2
  thread = run_docker_report(agent_tag, app_name)
  sleep 1

  [app_name, thread]
end

def run_docker_report(agent_tag, container_ids)
  Thread.new do
    output_dir = "#{ENV['DOCKER_MONITOR_OUTPUT_DIR']}/#{sanitize_tag(agent_tag)}"
    env_str = ''
    env_str += "-e TEST_TAG=#{ENV['TEST_TAG']} "
    env_str += "-e AGENT_VERSION=#{agent_tag} "
    env_str += "-e DOCKER_MONITOR_OUTPUT_DIR=#{output_dir} "
    env_str += "-e MONITOR_CONTAINERS=#{container_ids} "

    docker_mount_bind = '--mount type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock'
    output_mount_bind = "--mount type=bind,source=./#{output_dir},target=/app/#{output_dir}"

    command = "cd ./test/perfverse/docker_monitor && mkdir -p #{output_dir} && "
    command << "sudo docker run --rm --name docker_monitor_report #{env_str} #{docker_mount_bind} #{output_mount_bind} docker_monitor_report:local"

    output_line('Running docker monitor report')
    output = run_command(command)

    output_line("Docker Monitor Report Output: \n" + output)
  end
end

###############################################################################

iteration_index = ENV['ITERATION_INDEX'].to_i
# A plain rotate(iteration_index) only redistributes which tag lands in absolute position 1 --
# it preserves the cyclic adjacency between tags (whichever tag is coded immediately after
# another always stays immediately after it, every iteration). That's enough to average out a
# "which VM/how far into the job" effect, but not a "runs right after tag X" carryover effect --
# confirmed via an identical-code control (every tag pointing at the same commit still showed a
# sustained ~10-20% response-time gap between tags under plain rotation). Shuffling per iteration
# (seeded by iteration_index for reproducibility) breaks adjacency too, not just starting offset.
tags = JSON.parse(ENV['AGENT_TAGS']).map { |t| transform_agent_tags(t) }.shuffle(random: Random.new(iteration_index))
output_line("Running perf test for iteration #{iteration_index} with #{ENV['RUN_TIME']} run time, tags (shuffled): #{tags.map(&:first)}")

pull_locust
build_docker_monitor_report

tags.each do |agent_tag, env_vars|
  build_rails_app(agent_tag)

  app_name, monitor_thread = run_rails_app(agent_tag, env_vars)
  run_traffic(agent_tag)

  shutdown_rails_app(app_name)
  monitor_thread.join
end
