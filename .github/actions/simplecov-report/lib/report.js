"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || function (mod) {
    if (mod && mod.__esModule) return mod;
    var result = {};
    if (mod != null) for (var k in mod) if (k !== "default" && Object.prototype.hasOwnProperty.call(mod, k)) __createBinding(result, mod, k);
    __setModuleDefault(result, mod);
    return result;
};
var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.report = void 0;
const core = __importStar(require("@actions/core"));
const github = __importStar(require("@actions/github"));
const actions_replace_comment_1 = __importDefault(require("@aki77/actions-replace-comment"));
const markdown_table_1 = require("markdown-table");
function report(coveredPercent, failedThreshold, coveredPercentBranch, failedThresholdBranch) {
    return __awaiter(this, void 0, void 0, function* () {
        let results = [['', 'Coverage', 'Threshold'],
            ['Line', `${coveredPercent}%`, `${failedThreshold}%`]];
        if (coveredPercentBranch) {
            results.push(['Branch', `${coveredPercentBranch}%`, `${failedThresholdBranch}%`]);
        }
        const summaryTable = (0, markdown_table_1.markdownTable)(results);
        const pullRequestId = github.context.issue.number;
        if (!pullRequestId) {
            throw new Error('Cannot find the PR id.');
        }
        yield (0, actions_replace_comment_1.default)({
            token: core.getInput('token', { required: true }),
            owner: github.context.repo.owner,
            repo: github.context.repo.repo,
            issue_number: pullRequestId,
            body: `## Simplecov Report
${summaryTable}
`
        });
    });
}
exports.report = report;
