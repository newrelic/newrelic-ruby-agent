import type { Context } from '@actions/github/lib/context';
import type { components } from '@octokit/openapi-types';
import type { Octokit } from '@technote-space/github-action-helper/dist/types';
import type { Logger } from '@technote-space/github-action-log-helper';
type ActionsListJobsForWorkflowRunResponseData = components['schemas']['job'];
export declare const getTargetRunId: (context: Context) => number;
export declare const getJobs: (octokit: Octokit, context: Context) => Promise<Array<ActionsListJobsForWorkflowRunResponseData>>;
export declare const getJobConclusions: (jobs: Array<{
    conclusion: string | null;
}>) => Array<string>;
export declare const getWorkflowConclusion: (conclusions: Array<string>) => string;
export declare const execute: (logger: Logger, octokit: Octokit, context: Context) => Promise<void>;
export {};
