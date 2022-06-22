import path from 'path'
import * as core from '@actions/core'
import * as github from '@actions/github'
import {report} from './report'

interface Result {
  result: {
    covered_percent?: number // NOTE: simplecov < 0.21.0
    line?: number
    branch?: number | undefined
  }
}

async function run(): Promise<void> {
  try {
    if (!github.context.issue.number) {
      core.warning('Cannot find the PR id.')
      return
    }

    const failedThreshold: number = Number.parseInt(core.getInput('failedThreshold'), 10)
    core.debug(`failedThreshold ${failedThreshold}`)

    const failedThresholdBranch: number = Number.parseInt(core.getInput('failedThresholdBranch'), 10)
    core.debug(`failedThresholdBranch ${failedThresholdBranch}`)

    const resultPath: string = core.getInput('resultPath')
    core.debug(`resultPath ${resultPath}`)

    // eslint-disable-next-line @typescript-eslint/no-non-null-assertion, @typescript-eslint/no-require-imports, @typescript-eslint/no-var-requires
    const json = require(path.resolve(process.env.GITHUB_WORKSPACE!, resultPath)) as Result
    const coveredPercent = json.result.covered_percent ?? json.result.line
    const coveredPercentBranch = json.result.branch

    if (coveredPercent === undefined) {
      throw new Error('Coverage is undefined!')
    }

    await report(coveredPercent, failedThreshold, coveredPercentBranch, failedThresholdBranch)

    if (coveredPercent < failedThreshold) {
      throw new Error(`Line coverage is less than ${failedThreshold}%. (${coveredPercent}%)`)
    }
    if ((coveredPercentBranch !== undefined) && (coveredPercentBranch < failedThresholdBranch)) {
      throw new Error(`Branch coverage is less than ${failedThresholdBranch}%. (${coveredPercentBranch}%)`)
    }
  } catch (error) {
    if (error instanceof Error) {
      core.setFailed(error.message)
    }
  }
}

run()
