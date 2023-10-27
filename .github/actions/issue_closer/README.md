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

## Contributing

- Clone the repo containing the action
- Make sure you have Node.js (the action was originally tested with version 18 LTS) and Yarn installed
- In the directory containing this `README.md` file and the `package.json` file, run `yarn install`
- Make your desired changes to `index.js`
    - note: ignore `dist/index.js`, as it is only intended for use by GitHub Actions
- Test your changes with `node index.js` and/or `yarn run test`
- Lint your changes with `yarn run lint`
- Regenerate the distribution file `dist/index.js` by running `yarn run package`
- Submit a PR with your changes
