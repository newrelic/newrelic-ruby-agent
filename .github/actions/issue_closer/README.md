# Issue Closer JavaScript GitHub Action

GitHub will automatically close an issue when a PR containing a "resolves #1234"
type comment is merged, but only if the PR is merged into the default branch.

This action will close any issue referenced by a merged PR regardless of the
branch the PR was merged into.

## Inputs

token: A GitHub token with permission to read PR body text, read PR comments,
       and close referenced GitHub issues.

## Outputs

(none)

## Example usage

```yaml
# Example GitHub Workflow
name: PR Closed

on:
  pull_request:
    types:
      - closed

jobs:
  issue_closer:
    if: github.event.pull_request.merged == true
    runs-on: ubuntu-latest
    permissions: write-all
    steps:
        uses: actions/issue-closer
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
```
