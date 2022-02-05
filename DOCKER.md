# Using Docker with the New Relic Ruby Agent

These instructions will guide you through the process of setting up Docker for
use with developing the New Relic Ruby Agent. The use of Docker containers can
provide for a consistent experience free from machine specific issues.

## Install Docker

You will need to have [Docker Desktop](https://www.docker.com/) installed and
running on your machine.

If you are using on macOS and using [Homebrew](https://brew.sh/), Docker can be
installed as a cask via:

```shell
$ brew install --cask docker
```

and then launched via the `/Applications/Docker.app` launcher that is installed.

For alternatives to using macOS with Homebrew, see Docker's
[Get Started Guide](https://www.docker.com/get-started).


## Clone the project

Use git to clone the [newrelic/newrelic-ruby-agent](https://github.com/newrelic/newrelic-ruby-agent)
project.

The [Dockerfile](Dockerfile) and [docker-compose.yml](docker-compose.yml)
files are located in the root of the project, where this `DOCKER.md`
document resides.


## Run Docker Compose

Docker Compose launches multiple containers simultaneously to support the
running of the functional tests that require a variety of data handling
server applications such as PostgreSQL, Redis, memcached, etc. Each one of
these server applications uses its own container and then there's a Ruby
container (referred to as the "app" container) that runs the minitest tests
while connecting to the other containers.

In one shell session, change to the root of the project and then bring up all
containers with Docker Compose:

```shell
$ docker-compose up
```

In a separate shell session (probably in a separate terminal split, tab, or
window), execute the 'test_all' or 'test_one' helper scripts to test standard,
environment, and multiverse tests against all Rubies or a single Ruby.

```shell
$ docker-compose exec app test_one 3.1.0

# or

$ docker-compose exec app test_all
```

In lieu of running the tests, an interactive Bash shell can be
launched against the running Ruby app container for development and/or
debugging. While the `docker-compose up` shell session is still running,
bring up an additional local shell session and run the following:

```shell
$ docker-compose exec app bash
```

You will be dropped at a Bash prompt as the root user, with multiple
Rubies installed at `/root/.rubies`. Make use of the `ruby_run` helper
script to run Ruby commands for a specific Ruby version:

```shell
docker bash> ruby_run 3.1.0 bundle exec ls
```


## Output

When using Docker Compose, one shell session will produce STDOUT output that
pertains to all of the services (MySQL, MongoDB, etc.) and the other shell
session will produce STDOUT output related to the Ruby based functional tests.
Both streams of output may provide information about any errors or warnings
that take place.


## Cleanup

Invoking `ctrl-c` in the shell session that is running the `docker-compose up`
command should suffice to prompt Docker Compose to shut down all running
containers. Otherwise, `docker-compose down` can be ran.

Use `docker ps -a` to show a list of all containers. Pass a container id to
`docker rm` (ex: `docker rm 5c15ee2f1c4f`) to remove it.

Use `docker images` to show a list of all images. Typically, you'll want to
keep these images if you plan on running Docker with them again in the future.
If you are done with them, you can pass an image id to `docker rmi` to remove
an image (ex: `docker rmi 4253856b2570`).


## Questions, Feature Requests, Contributions, etc.

The maintainers of New Relic's Ruby agent project are hopeful that the use of
containers and these instructions can provide consistency and a lowered barrier
of entry when it comes to providing contributions to the agent project itself.

For questions, feature requests, proposals to support Podman, PRs to improve
behavior or documentation, etc., please see [CONTRIBUTING.md](CONTRIBUTING.md).
