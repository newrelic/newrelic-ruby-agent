const core = require('@actions/core');
const github = require('@actions/github');
const octokit_graphql = require('@octokit/graphql');

const DEFAULT_BRANCH = 'dev';
const COMMENT_COUNT = 100;
const RESPONSE_SUCCESS = 200;

async function prComments(owner, repo, number, token) {
  const query = `query { 
    repository(owner: "${owner}", name: "${repo}") {
      pullRequest(number: ${number}) {
        comments(last: ${COMMENT_COUNT}) {
          edges {
            node {
              bodyText
            }
          }
        },
        body
      }
    }
  }`;

  const results = await octokit_graphql.graphql({
    query: query,
    headers: {
      authorization: `token ${token}`
    }
  });

  const pr = results.repository.pullRequest;
  const combined = [pr.body]; // treat the PR body and comments as equals
  const comments = pr.comments.edges;
  let i = 0;
  while (i < comments.length) {
    combined.push(comments[i].node.bodyText);
    i++;
  }

  return combined;
}

async function issueNumbersFromComment(comment) {
  const pattern = /(?:close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved)\s+#(\d+)(?:(?:\s|,)+#(\d+))*/gi;
  const matches = pattern.exec(comment);

  if (matches) {
    matches.shift(); // $0 holds the entire match
    return matches.filter(ele => { return ele !== undefined; });
  } else {
    return;
  }
}

async function issueNumbersFromPRComments(comments) {
  let issueNumbers = [];
  let i = 0;
  while (i < comments.length) {
    const numbers = await issueNumbersFromComment(comments[i]);
    if (numbers) {
      issueNumbers = issueNumbers.concat(numbers);
    }
    i++;
  }
  return [...new Set(issueNumbers)]; // de-dupe
}

async function closeIssues(issueNumbers, owner, repo, token) {
  const octokit = github.getOctokit(token);

  let i = 0;
  while (i < issueNumbers.length) {
    console.log(`Using Octokit to close Issue #${issueNumbers[0]}...`);
    const response = await octokit.rest.issues.update({
      owner: owner,
      repo: repo,
      issue_number: issueNumbers[0],
      state: 'closed'
    });
    if (response.status != RESPONSE_SUCCESS) {
      throw `REST call to update issue ${issueNumbers[0]} failed - ${JSON.stringify(response)}`;
    }
    i++;
  }
}

async function run() {
  try {
    const token = core.getInput('token');
    if (!token) {
      throw 'Action input \'token\' is not set!';
    }

    const payload = github.context.payload;

    const action = payload.action;
    if (action != 'closed') {
      throw `Received invalid action of '${action}'. Expected 'closed'. Is a Workflow condition missing?`;
    }

    const number = payload.number;
    console.log(`The PR number is ${number}`);

    const base = payload.pull_request.base;

    const ref = base.ref;
    console.log(`The PR ref is ${ref}`);
    if (ref == DEFAULT_BRANCH) {
      console.log(`PR ${number} targeted branch ${ref}. Exiting.`);
      return;
    }

    const fullName = base.repo.full_name;
    console.log(`The repo full name is ${fullName}`);
    const repoElements = fullName.split('/');
    const owner = repoElements[0];
    const repo = repoElements[1];
    console.log(`PR repo owner = ${owner}, repo = ${repo}`);

    const comments = await prComments(owner, repo, number, token);
    const issueNumbers = await issueNumbersFromPRComments(comments);

    if (issueNumbers.length == 0) {
      console.log('No comments found with issue closing syntax');
      return;
    }

    console.log(`Issue ids in need of closing: ${issueNumbers}`);
    closeIssues(issueNumbers, owner, repo, token);
    console.log('Done');
  } catch (error) {
    core.setFailed(error.message);
  }
}

run();
