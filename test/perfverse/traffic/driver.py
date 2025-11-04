from locust import HttpUser, TaskSet, task, constant_throughput
from requests import Request, Session
import importlib
import os
import sys

sys.path.insert(0, os.environ.get("DRIVER_CONFIG_PATH"))

config = importlib.import_module(os.environ.get("DRIVER_CONFIG", "config"))


class Run(TaskSet):

    wait_time = constant_throughput(20)

    @task
    def hit_endpoints(self):
        for endpoint in config.requests:
            r = self.client.request(**endpoint)
            if r.status_code != 200:
                # if the application returns a non-200 show the errors and fail
                print(r)
                print(endpoint)
                sys.exit(-1)


class Driver(HttpUser):
    tasks = [Run]