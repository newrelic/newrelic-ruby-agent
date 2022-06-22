var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
var __generator = (this && this.__generator) || function (thisArg, body) {
    var _ = { label: 0, sent: function() { if (t[0] & 1) throw t[1]; return t[1]; }, trys: [], ops: [] }, f, y, t, g;
    return g = { next: verb(0), "throw": verb(1), "return": verb(2) }, typeof Symbol === "function" && (g[Symbol.iterator] = function() { return this; }), g;
    function verb(n) { return function (v) { return step([n, v]); }; }
    function step(op) {
        if (f) throw new TypeError("Generator is already executing.");
        while (_) try {
            if (f = 1, y && (t = op[0] & 2 ? y["return"] : op[0] ? y["throw"] || ((t = y["return"]) && t.call(y), 0) : y.next) && !(t = t.call(y, op[1])).done) return t;
            if (y = 0, t) op = [op[0] & 2, t.value];
            switch (op[0]) {
                case 0: case 1: t = op; break;
                case 4: _.label++; return { value: op[1], done: false };
                case 5: _.label++; y = op[1]; op = [0]; continue;
                case 7: op = _.ops.pop(); _.trys.pop(); continue;
                default:
                    if (!(t = _.trys, t = t.length > 0 && t[t.length - 1]) && (op[0] === 6 || op[0] === 2)) { _ = 0; continue; }
                    if (op[0] === 3 && (!t || (op[1] > t[0] && op[1] < t[3]))) { _.label = op[1]; break; }
                    if (op[0] === 6 && _.label < t[1]) { _.label = t[1]; t = op; break; }
                    if (t && _.label < t[2]) { _.label = t[2]; _.ops.push(op); break; }
                    if (t[2]) _.ops.pop();
                    _.trys.pop(); continue;
            }
            op = body.call(thisArg, _);
        } catch (e) { op = [6, e]; y = 0; } finally { f = t = 0; }
        if (op[0] & 5) throw op[1]; return { value: op[0] ? op[1] : void 0, done: true };
    }
};
define("report", ["require", "exports", "@actions/core", "@actions/github", "@aki77/actions-replace-comment", "markdown-table"], function (require, exports, core, github, actions_replace_comment_1, markdown_table_1) {
    "use strict";
    exports.__esModule = true;
    exports.report = void 0;
    function report(coveredPercent, failedThreshold, coveredPercentBranch, failedThresholdBranch) {
        return __awaiter(this, void 0, void 0, function () {
            var summaryTable, pullRequestId;
            return __generator(this, function (_a) {
                switch (_a.label) {
                    case 0:
                        summaryTable = (0, markdown_table_1.markdownTable)([
                            ['', 'Coverage', 'Threshold'],
                            ['Line', "".concat(coveredPercent, "%"), "".concat(failedThreshold, "%")],
                            ['Branch', "".concat(coveredPercentBranch, "%"), "".concat(failedThresholdBranch, "%")]
                        ]);
                        pullRequestId = github.context.issue.number;
                        if (!pullRequestId) {
                            throw new Error('Cannot find the PR id.');
                        }
                        return [4 /*yield*/, (0, actions_replace_comment_1["default"])({
                                token: core.getInput('token', { required: true }),
                                owner: github.context.repo.owner,
                                repo: github.context.repo.repo,
                                issue_number: pullRequestId,
                                body: "## Simplecov Report\n".concat(summaryTable, "\n")
                            })];
                    case 1:
                        _a.sent();
                        return [2 /*return*/];
                }
            });
        });
    }
    exports.report = report;
});
define("main", ["require", "exports", "path", "@actions/core", "@actions/github", "report"], function (require, exports, path_1, core, github, report_1) {
    "use strict";
    exports.__esModule = true;
    function run() {
        var _a;
        return __awaiter(this, void 0, void 0, function () {
            var failedThreshold, failedThresholdBranch, resultPath, json, coveredPercent, coveredPercentBranch, error_1;
            return __generator(this, function (_b) {
                switch (_b.label) {
                    case 0:
                        _b.trys.push([0, 2, , 3]);
                        if (!github.context.issue.number) {
                            core.warning('Cannot find the PR id.');
                            return [2 /*return*/];
                        }
                        failedThreshold = Number.parseInt(core.getInput('failedThreshold'), 10);
                        core.debug("failedThreshold ".concat(failedThreshold));
                        failedThresholdBranch = Number.parseInt(core.getInput('failedThresholdBranch'), 10);
                        core.debug("failedThresholdBranch ".concat(failedThresholdBranch));
                        resultPath = core.getInput('resultPath');
                        core.debug("resultPath ".concat(resultPath));
                        json = require(path_1["default"].resolve(process.env.GITHUB_WORKSPACE, resultPath));
                        coveredPercent = (_a = json.result.covered_percent) !== null && _a !== void 0 ? _a : json.result.line;
                        coveredPercentBranch = json.result.branch;
                        if (coveredPercent === undefined) {
                            throw new Error('Coverage is undefined!');
                        }
                        return [4 /*yield*/, (0, report_1.report)(coveredPercent, coveredPercentBranch, failedThreshold, failedThresholdBranch)];
                    case 1:
                        _b.sent();
                        if (coveredPercent < failedThreshold) {
                            throw new Error("Line coverage is less than ".concat(failedThreshold, "%. (").concat(coveredPercent, "%)"));
                        }
                        if (coveredPercentBranch < failedThresholdBranch) {
                            throw new Error("Branch coverage is less than ".concat(failedThresholdBranch, "%. (").concat(coveredPercentBranch, "%)"));
                        }
                        return [3 /*break*/, 3];
                    case 2:
                        error_1 = _b.sent();
                        if (error_1 instanceof Error) {
                            core.setFailed(error_1.message);
                        }
                        return [3 /*break*/, 3];
                    case 3: return [2 /*return*/];
                }
            });
        });
    }
    run();
});
