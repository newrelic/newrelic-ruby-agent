# SimpleCov Report

A GitHub Action that reports SimpleCov coverage.

![Demo](https://i.gyazo.com/c4e572c91fe8048c95392ea3ddce79f5.png)

## Usage:

The action works only with `pull_request` event.

### Inputs

- `token` - The GITHUB_TOKEN secret.
- `failedThreshold` - Failed threshold. (default: `93`)
- `resultPath` - Path to last_run json file. (default: `coverage/.last_run.json`)

## Example

```yaml
name: Tests
on:
  pull_request:

jobs:
  build:
    steps:
      - name: Test
        run: bundle exec rspec

      - name: SimpleCov Report
        uses: aki77/simplecov-report-action@v1
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
```
