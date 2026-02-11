import os
import sys
import json
import threading
import docker
import signal
import datetime
import time

def output_stats(log, stats):
    try:
        time_read = stats['read']
        container_id = stats['id']
        container_name = stats['name'].lstrip('/').strip()
        cpu_usage = stats['cpu_stats']['cpu_usage']['total_usage']
        precpu_usage = stats['precpu_stats']['cpu_usage']['total_usage']
        cpu_system = stats['cpu_stats']['system_cpu_usage']
        precpu_system = stats['precpu_stats']['system_cpu_usage']
        memory_usage = stats['memory_stats']['usage']
        stats_cache = stats['memory_stats']['stats']['inactive_file']
        memory_limit = stats['memory_stats']['limit']
        network_input = stats['networks']['eth0']['rx_bytes']
        network_output = stats['networks']['eth0']['tx_bytes']
        number_cpus = stats['cpu_stats']['online_cpus']

        used_memory = memory_usage - stats_cache
        available_memory = memory_limit
        memory_usage_perc = (used_memory / available_memory) * 100.0
        cpu_delta = cpu_usage - precpu_usage
        system_cpu_delta = cpu_system - precpu_system
        cpu_usage_perc= (cpu_delta / system_cpu_delta) * number_cpus * 100.0

        log.write(f"{time_read}, {container_name}, {cpu_usage}, {cpu_system}, {memory_usage}, {stats_cache}, {memory_limit}, {network_input}, {network_output}, {number_cpus}, {used_memory}, {available_memory}, {memory_usage_perc}, {cpu_delta}, {system_cpu_delta}, {cpu_usage_perc}\n")
        log.flush()

        #return used_memory, available_memory, memory_usage_perc, cpu_delta, system_cpu_delta, cpu_usage_perc
    except KeyError as e:
        #print(f"KeyError: {e}")
        #traceback.print_exc()
        return

def read_from_container(client, log, container_id):
    container = client.containers.get(container_id)
    for stat in container.stats(stream=True, decode=True):
        print(f"Time: {stat['read']} Container: {container_id} name: {stat['name']}", flush=True)
        output_stats(log, stat)


def sigterm_handler(signum, frame):
    print("SIGTERM received, exiting gracefully...")
    sys.exit(0)

if __name__ == "__main__":
    # Register the signal handler for SIGTERM
    signal.signal(signal.SIGTERM, sigterm_handler)

    client = docker.from_env()

    dockermon_output_dir = os.environ.get("DOCKER_MONITOR_OUTPUT_DIR")
    container_ids = os.environ.get("MONITOR_CONTAINERS")
    container_ids = container_ids.split(",")
    print(f"Monitoring containers specified by MONITOR_CONTAINERS: {container_ids}")

    # directory where the stats are stored
    if dockermon_output_dir is None or len(dockermon_output_dir) == 0:
        print("Error: DOCKER_MONITOR_OUTPUT_DIR is not set")
        exit(1)

    # create output directory
    output_dir = f"{dockermon_output_dir}/"
    os.makedirs(output_dir, exist_ok=True)

    print(f"Output directory: {output_dir}", flush=True)

    # generate unqiue filename for CSV
    output_file = "docker-monitor"
    output_file += f"-{os.uname().nodename}"
    output_file += f"-{datetime.datetime.now().strftime('%Y-%m-%d_%H-%M-%S')}"
    output_file += ".csv"
    output_file_name = output_file
    output_file = os.path.join(output_dir, output_file)
    print(f"Output file: {output_file}", flush=True)

    # create a JSON file with the metadata
    json_file = open(os.path.join(output_dir, "metadata.json"), "w")
    metadata = {}
    agent_version = os.environ.get("AGENT_VERSION")
    test_tag = os.environ.get("TEST_TAG")

    metadata['agent_version'] = agent_version
    metadata['x_axis'] = print(f"{agent_version}_{test_tag}")
    metadata['container_ids'] = container_ids
    metadata['output_file'] = output_file
    metadata['output_file_name'] = output_file
    metadata['TEST_TAG'] = test_tag

    json_file.write(json.dumps(metadata, indent=4))
    json_file.close()

    log = open(output_file, "w")
    log.write("Time,Container Name,cpu_usage,cpu_system,memory_usage,stats_cache,memory_limit,network_input,network_output,number_cpus,used_memory,available_memory,memory_usage_perc,cpu_delta,system_cpu_delta,cpu_usage_perc\n")

    print(f"Starting monitors for containers f{container_ids}", flush=True)

    threads = []
    for i in range(len(container_ids)):
        thread = threading.Thread(target=read_from_container, args=(client, log, container_ids[i]))
        threads.append(thread)

    for i in range(len(threads)):
        threads[i].start()

    for i in range(len(threads)):
        threads[i].join()

