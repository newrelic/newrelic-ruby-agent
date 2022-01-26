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
$ brew cask install docker
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


## Using just the Dockerfile (unit tests and standalone dev only)

The project `Dockerfile` can be used by itself to run the project unit tests.
Docker Compose and the project `docker-compose.yml` file will be needed to
run functional tests which involve communicating with data systems such as
PostgreSQL and Redis.

To only run the unit tests using `Dockerfile` by itself, first change
directories to the root of the project, then build an image, and
finally run a container from the image:

```shell
$ cd /path/to/project/git/clone
$ docker build -t newrelic/newrelic-ruby-agent-tester .
$ docker run -it newrelic/newrelic-ruby-agent-tester
```

* `build -t <TAG>` applies a tag to the image during building
* `.` indicates "here" and tells Docker that the `Dockerfile` file can be found
  in the current directory
* `run -it` tells Docker to run interactively (`i`) and with a pseudo TTY (`t`)


## Using Docker Compose (for functional tests and dev involving services)

Docker Compose launches multiple containers simultaneously to support the
running of the functional tests that require a variety of data handling
server applications such as PosgreSQL, Redis, memcached, etc. Each one of
these server applications uses its own container and then there's a Ruby
container (referred to as the "app" container) that runs the Minitest tests
while connecting to the other containers.

In one shell session, change to the root of the project and then bring up all
containers with Docker Compose:

```shell
$ docker-compose up
```

In a separate shell session (probably in a separate terminal split, tab, or
window), execute the 'test:all' rake task to test all standard, environment,
and multiverse tests:

```shell
$ docker-compose exec app bundle exec rake test:all
```

In lieu of running the tests, an interactive Bash shell can be
launched against the running Ruby app container for development and/or
debugging. While the `docker-compose up` shell session is still running,
bring up an additional local shell session and run the following:

```shell
$ docker-compose exec app bash
```

You will be dropped at a Bash prompt as the "relic" user, with "ruby" and
"bundle" in your PATH.


## Output

When using Docker Compose, one shell session will produce STDOUT output that
pertains to all of the services (MySQL, MongoDB, etc.) and the other shell
session will produce STDOUT output related to the Ruby based functional tests.
Both streams of output may provide information about any errors or warnings
that take place.


## Cleanup

If the project `Dockerfile` is being used without Docker Compose, then use
`docker ps` to show information about containers and `docker images`
for information about images. The `docker stop`, `docker kill`, `docker rm`
and `docker rmi` commands can be used with the appropriate container and image
ids. Run `docker --help` or read through the hosted [CLI documentation](https://docs.docker.com/engine/reference/commandline/docker/).

When Docker Compose is used, invoking `ctrl-c` in the shell session that is
running the `docker-compose up` command should suffice to prompt Docker Compose
to shut down all running containers. Otherwise, `docker-compose down` can be
ran after the `docker-compose up` process has been stopped. All relevant
containers and images can then be optionally discarded using the `docker` CLI
commands described in the previous paragraph.


## Questions, Feature Requests, Contributions, etc.

The maintainers of New Relic's Ruby agent project are hopeful that the use of
containers and these instructions can provide consistency and a lowered barrier
of entry when it comes to providing contributions to the agent project itself.

For questions, feature requests, proposals to support Podman, PRs to improve
behavior or documentation, etc., please see [CONTRIBUTING.md](CONTRIBUTING.md).
