# The Perfverse

## Overview

Performance test for the agent that runs in GHA. To run the Perfverse, go to [Github Actions](https://github.com/newrelic/newrelic-ruby-agent/actions/workflows/run_perfverse.yml) to run the workflow. 


### Agent Version and Agent Configs

Each run will run a specific git tag with whatever env vars you set passed in to the agent. Agent config env vars are optional, and do not need to be listed. 

Expected String format:

    git_tag:ENV_VAR_1=one;ENV_VAR_2=two


### Github Actions 

Designed to be run in GHA by triggering the workflow dispatch with the expected inputs. 
The GHA files used to run the perfverse:

- `.github/workflows/run_perfverse.yml`
- `.github/workflows/scripts/run_perf_tests.rb`
- `.github/actions/run_perfverse/action.yml`


## Running Locally

While it's designed to run in GHA, individual parts of this can be run locally for testing and development purposes.

### Rails app

Will build a rails app running the agent from a specific git tag. All versions also have git tags, so any version number can be used. 
Currently we only have a single rails 7 app. You will need to pass in the new relic staging license key as an env var (or use prod and remove the host config). 

    cd ./test/perfverse/

    docker build --pull --build-arg AGENT_VERSION=9.0.0 --progress=plain -t ruby_perf_app:local .

    docker run --rm --name perfverse_local -e NEW_RELIC_LICENSE_KEY=$NR_LICENSE_KEY -e NEW_RELIC_APP_NAME=perfverse_local -e NEW_RELIC_HOST=staging-collector.newrelic.com -e s -p 3000:3000 ruby_perf_app:local


### Dockermon

The container it will be monitoring needs to be already running, and it will run until that container stops. It will then output a metadata.json file and a csv file with all the stats recorded.

Env vars you will need to pass in to dockermon: MONITOR_CONTAINERS, AGENT_VERSION, DOCKER_MONITOR_OUTPUT_DIR. There also need to be some volume mounts, one for it to connect to the Docker socket and another for the output directory.

    cd ./test/perfverse/docker_monitor 
    mkdir -p docker_monitor_outputs

    docker build --pull --progress=plain -t docker_monitor_report:local . 

    docker run --rm --name docker_monitor_report -e MONITOR_CONTAINERS=perfverse_local -e AGENT_VERSION=9.0.0 -e DOCKER_MONITOR_OUTPUT_DIR=docker_monitor_outputs --mount type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock --mount type=bind,source=./docker_monitor_outputs,target=/app/docker_monitor_outputs docker_monitor_report:local


### Locust

This is the traffic driver. It is configured to provide a consistent load on the application being tested. You can change how long you want it to run by modifying the value of the `-t` flag.

    cd ./test/perfverse/traffic 
    
    docker pull locustio/locust

    docker run -p 8089:8089 --network=\"host\" -v $PWD:/mnt/locust locustio/locust -t 1m -f /mnt/locust/driver.py --host=http://127.0.0.1:3000 --headless -u 5



### Graphs

This will create all the graphs from the dockermon data. It is expecting to find zip files in the inputs directory that are the ouput of several dockermon outputs. (Set up to upload and download artifacts on GHA). All graphs will be put in the outputs folder.

    cd ./test/perfverse/reports

    mkdir -p inputs 
    mkdir -p outputs

    docker build --pull --progress=plain -t charty:local . 
    docker run --rm --name ruby-charty --network="host" -it --mount type=bind,source=./output,target=/charty/output charty:local

