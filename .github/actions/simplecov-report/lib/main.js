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
const path_1 = __importDefault(require("path"));
const core = __importStar(require("@actions/core"));
const github = __importStar(require("@actions/github"));
const report_1 = require("./report");
function run() {
    var _a;
    return __awaiter(this, void 0, void 0, function* () {
        try {
            if (!github.context.issue.number) {
                core.warning('Cannot find the PR id.');
                return;
            }
            const failedThreshold = Number.parseInt(core.getInput('failedThreshold'), 10);
            core.debug(`failedThreshold ${failedThreshold}`);
            const failedThresholdBranch = Number.parseInt(core.getInput('failedThresholdBranch'), 30);
            core.debug(`failedThresholdBranch ${failedThresholdBranch}`);
            const resultPath = core.getInput('resultPath');
            core.debug(`resultPath ${resultPath}`);
            // eslint-disable-next-line @typescript-eslint/no-non-null-assertion, @typescript-eslint/no-require-imports, @typescript-eslint/no-var-requires
            const json = require(path_1.default.resolve(process.env.GITHUB_WORKSPACE, resultPath));
            const coveredPercent = (_a = json.result.covered_percent) !== null && _a !== void 0 ? _a : json.result.line;
            const coveredPercentBranch = json.result.branch;
            if (coveredPercent === undefined) {
                throw new Error('Coverage is undefined!');
            }
            yield (0, report_1.report)(coveredPercent, failedThreshold, coveredPercentBranch, failedThresholdBranch);
            if (coveredPercent < failedThreshold) {
                throw new Error(`Line coverage is less than ${failedThreshold}%. (${coveredPercent}%)`);
            }
            if (coveredPercentBranch && coveredPercentBranch < failedThresholdBranch) {
                throw new Error(`Branch coverage is less than ${failedThresholdBranch}%. (${coveredPercentBranch}%)`);
            }
        }
        catch (error) {
            if (error instanceof Error) {
                core.setFailed(error.message);
            }
        }
    });
}
run();
