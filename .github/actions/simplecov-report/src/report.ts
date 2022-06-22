import * as core from '@actions/core'
import * as github from '@actions/github'
import replaceComment from '@aki77/actions-replace-comment'
import {markdownTable} from 'markdown-table'

export async function report(coveredPercent: number, failedThreshold: number): Promise<void> {
  const summaryTable = markdownTable([
    ['Covered', 'Threshold'],
    [`${coveredPercent}%`, `${failedThreshold}%`]
  ])

  const pullRequestId = github.context.issue.number
  if (!pullRequestId) {
    throw new Error('Cannot find the PR id.')
  }

  await replaceComment({
    token: core.getInput('token', {required: true}),
    owner: github.context.repo.owner,
    repo: github.context.repo.repo,
    issue_number: pullRequestId,
    body: `## Simplecov Report
${summaryTable}
`
  })
}
