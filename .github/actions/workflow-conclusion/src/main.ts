import { resolve } from 'path';
import { setFailed } from '@actions/core';
import { Context } from '@actions/github/lib/context';
import { ContextHelper, Utils } from '@technote-space/github-action-helper';
import { Logger } from '@technote-space/github-action-log-helper';
import { execute } from './process';

const run = async(): Promise<void> => {
  const logger  = new Logger();
  const context = new Context();
  ContextHelper.showActionInfo(resolve(__dirname, '..'), logger, context);

  await execute(logger, Utils.getOctokit(), context);
};

run().catch(error => {
  console.log(error);
  setFailed(error.message);
});
