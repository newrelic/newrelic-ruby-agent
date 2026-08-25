# New Relic Ruby Agent - Development Guide

This file contains project-specific development information for Claude Code and developers.

## Repository Information

- **Main branch**: `dev` (not `main`)
- **Language**: Ruby
- **Test Framework**: Minitest
- **Docker**: Using Rancher Desktop (not Docker Desktop)
- **Test App Repository**: A separate local repo (e.g. `ruby_agent_playground`) for creating standalone test applications to experiment with agent features

---

## Testing

### Test Aliases (from ~/.bash_profile)

The repository uses custom test runner aliases (defined per-developer, pointing at `test/script/run_tests` in your local checkout):

```bash
bert    # Run unit tests:  test/script/run_tests -u
bere    # Run env tests:   test/script/run_tests -e
berm    # Run multiverse:  test/script/run_tests -m
bermq   # Run multiverse (quiet): test/script/run_tests -q
ber     # Run all tests:   test/script/run_tests
```

This is the path to the file that runs those commands (relative to the repo root): `test/script/run_tests`

### Multiverse Tests

**What are they?**
Multiverse tests are integration tests that run against multiple versions of gems (Rails, ActiveRecord, etc.) to ensure compatibility.

**Location**: `test/multiverse/suites/`

**How to run:**
```bash
berm <suite_name>          # Run a specific multiverse suite

# Examples:
berm active_record         # ActiveRecord with MySQL
berm active_record_pg      # ActiveRecord with PostgreSQL
berm rails                 # Rails tests
berm redis                 # Redis tests
```

**Via Rake:**
```bash
bundle exec rake test:multiverse[suite_name]
```

### Unit Tests

**How to run:**
```bash
bert                                    # Run all unit tests
bundle exec rake test                   # Alternative

# Run specific test file:
bundle exec rake test TEST=test/new_relic/agent/database_test.rb

# Run specific test by line number:
TEST=test/new_relic/agent/database_test.rb:42 bundle exec rake test
```

### Environment Tests

**How to run:**
```bash
bere                        # Run environment tests
bundle exec rake test:env[norails]     # Run with specific environment
```

---

## Docker Setup

### Running Services

The project uses Docker Compose with the following services:
- **PostgreSQL**: postgres:14.2 (port 5432)
- **MySQL**: mysql:5.7 (port 3306)
- **Redis**: redis:6.2.6 (port 6379)
- **MongoDB**: mongo:5.0.4 (port 27017)
- **Memcached**: memcached:1.6.12 (port 11211)
- **RabbitMQ**: rabbitmq:3.9.12
- **Elasticsearch 7**: elasticsearch:7.16.2 (port 9200)
- **Elasticsearch 8**: elasticsearch:8.13.0 (port 9250)

**Managing services:**
```bash
docker compose up -d           # Start all services
docker compose ps              # Check status
docker compose stop postgres   # Stop specific service
docker compose restart postgres # Restart specific service
```

**Note**: If using Rancher Desktop instead of Docker Desktop, the Docker CLI is typically at `~/.rd/bin/docker` (add it to your `PATH` if `docker` isn't found)

### Database Configuration

**PostgreSQL:**
- Host: `localhost` (when running tests on Mac)
- Host: `postgres` (when running inside Docker)
- Port: `5432`
- Username: `admin` (from docker-compose.yml)
- Password: `postgres_password`

**Environment variables for tests:**
```bash
export POSTGRES_USERNAME=admin
export POSTGRES_PASSWORD=postgres_password
```

**MySQL:**
- Host: `localhost` or `mysql`
- Port: `3306`
- Username: `root`
- Password: `mysql_root_password`

---

## Git Workflow

### Branches
- **Main development branch**: `dev` (NOT `main`)
- Create feature branches from `dev`
- PR target: `dev`

### Committing
- **Never commit automatically** - always let the developer review first

---

## Configuration

### Agent Configuration
- Main config file: `lib/new_relic/agent/configuration/default_source.rb`
- Test config: `test/multiverse/suites/*/config/newrelic.yml`
- Example configs: Various files in `test/` directories

### Ruby Version Management
- Using `rbenv`
- Current Ruby: 3.4.8
- Check with: `ruby -v`
- Switch with: `rbenv local <version>`

---

## Common Development Tasks

### Running RuboCop
```bash
rubo                    # Alias for: bundle exec rubocop -a
bundle exec rubocop -a  # Full command
```

### Database Migrations (for multiverse tests)
Migrations are auto-run when multiverse tests start. Located in:
`test/multiverse/suites/active_record*/db/migrate/`

### Checking Test Coverage
```bash
COVERAGE=true bundle exec rake test
# Results in: lib/coverage_*/.resultset.json
```

---

## Troubleshooting

### PostgreSQL Connection Issues
If tests can't connect to PostgreSQL:
1. Check if container is running: `docker compose ps`
2. Verify port is exposed: `docker ps | grep postgres` (should show `0.0.0.0:5432->5432/tcp`)
3. Check if port is listening: `lsof -i :5432`
4. Restart container: `docker compose restart postgres`

### MySQL Connection Issues
Similar to PostgreSQL, check container status and port exposure.

### Bundler Issues
```bash
bun    # Alias for: rm ./Gemfile.lock && bundle
```

---

## Project Structure

```
newrelic-ruby-agent/
├── lib/
│   └── new_relic/
│       ├── agent/                    # Core agent code
│       │   ├── configuration/        # Configuration handling
│       │   ├── database.rb          # SQL parsing and obfuscation
│       │   ├── datastores/          # Datastore instrumentation
│       │   └── instrumentation/     # Auto-instrumentation
│       └── control/
├── test/
│   ├── new_relic/                   # Unit tests
│   ├── multiverse/                  # Integration tests
│   │   ├── lib/                     # Multiverse framework
│   │   └── suites/                  # Test suites
│   └── environments/                # Environment tests
└── docker-compose.yml               # Service definitions
```

---

## Key Files

- **`lib/new_relic/agent/database.rb`** - SQL parsing, obfuscation, query naming
- **`lib/new_relic/agent/datastores/metric_helper.rb`** - Datastore metric generation
- **`lib/new_relic/agent/transaction/datastore_segment.rb`** - Datastore segment tracking
- **`lib/new_relic/agent/configuration/default_source.rb`** - All configuration options
- **`Rakefile`** - Test task definitions
- **`lib/tasks/tests.rake`** - Unit test task definitions

---

## Notes

- The test suite uses a custom `refute_raises` pattern that doesn't count as assertions in minitest output
- Some tests may show "0 assertions" but still pass/fail correctly
- Multiverse tests bundle gems independently for each environment
- Environment tests use a custom runner in `test/environments/lib/environments/runner.rb`
