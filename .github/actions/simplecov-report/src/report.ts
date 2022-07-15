import * as core from '@actions/core'
import * as github from '@actions/github'
import replaceComment from '@aki77/actions-replace-comment'
import {markdownTable} from 'markdown-table'

export async function report(coveredPercent: number, failedThreshold: number, coveredPercentBranch: number | undefined, failedThresholdBranch: number): Promise<void> {
  let results: string[][] = [['','Coverage', 'Threshold'],
                   ['Line', `${coveredPercent}%`, `${failedThreshold}%`]]
  if (coveredPercentBranch){
    results.push(['Branch',`${coveredPercentBranch}%`,`${failedThresholdBranch}%`])
  }
  const summaryTable = markdownTable(results)

  const pullRequestId = github.context.issue.number
  if (!pullRequestId) {
    throw new Error('Cannot find the PR id.')
  }

  await replaceComment({
    token: core.getInput('token', {required: true}),
    owner: github.context.repo.owner,
    repo: github.context.repo.repo,
    issue_number: pullRequestId,
    body: `## SimpleCov Report
${summaryTable}
`
  })
}
