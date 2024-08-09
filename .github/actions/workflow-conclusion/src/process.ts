import type { Context } from '@actions/github/lib/context';
import type { components } from '@octokit/openapi-types';
import type { Octokit } from '@technote-space/github-action-helper/dist/types';
import type { Logger } from '@technote-space/github-action-log-helper';
import { setOutput, exportVariable, getInput } from '@actions/core';
import { Utils } from '@technote-space/github-action-helper';
import { CONCLUSIONS } from './constant';

type ActionsListJobsForWorkflowRunResponseData = components['schemas']['job'];

export const getTargetRunId = (context: Context): number => /^\d+$/.test(getInput('TARGET_RUN_ID')) ? Number(getInput('TARGET_RUN_ID')) : context.runId;

export const getJobs = async(octokit: Octokit, context: Context): Promise<Array<ActionsListJobsForWorkflowRunResponseData>> => octokit.paginate(
  octokit.rest.actions.listJobsForWorkflowRun,
  {
    ...context.repo,
    'run_id': getTargetRunId(context),
  },
);

export const getJobConclusions = (jobs: Array<{ conclusion: string | null }>): Array<string> => Utils.uniqueArray(
  jobs
    .filter((job): job is { conclusion: string } => null !== job.conclusion)
    .map(job => job.conclusion),
);

export const getWorkflowConclusion = (conclusions: Array<string>): string =>
  !conclusions.length ? getInput('FALLBACK_CONCLUSION') :
    Utils.getBoolValue(getInput('STRICT_SUCCESS')) ?
      conclusions.some(conclusion => conclusion !== 'success') ? 'failure' : 'success' :
      CONCLUSIONS.filter(conclusion => conclusions.includes(conclusion)).slice(-1)[0] ?? getInput('FALLBACK_CONCLUSION');

export const execute = async(logger: Logger, octokit: Octokit, context: Context): Promise<void> => {
  const jobs        = await getJobs(octokit, context);
  const conclusions = getJobConclusions(jobs);
  const conclusion  = getWorkflowConclusion(conclusions);

  logger.startProcess('Jobs: ');
  console.log(jobs);

  logger.startProcess('Conclusions: ');
  console.log(conclusions);

  logger.startProcess('Conclusion: ');
  console.log(conclusion);

  setOutput('conclusion', conclusion);
  const envName = getInput('SET_ENV_NAME');
  if (envName) {
    exportVariable(envName, conclusion);
  }
};
