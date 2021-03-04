module.exports =
/******/ (function(modules, runtime) { // webpackBootstrap
/******/ 	"use strict";
/******/ 	// The module cache
/******/ 	var installedModules = {};
/******/
/******/ 	// The require function
/******/ 	function __webpack_require__(moduleId) {
/******/
/******/ 		// Check if module is in cache
/******/ 		if(installedModules[moduleId]) {
/******/ 			return installedModules[moduleId].exports;
/******/ 		}
/******/ 		// Create a new module (and put it into the cache)
/******/ 		var module = installedModules[moduleId] = {
/******/ 			i: moduleId,
/******/ 			l: false,
/******/ 			exports: {}
/******/ 		};
/******/
/******/ 		// Execute the module function
/******/ 		var threw = true;
/******/ 		try {
/******/ 			modules[moduleId].call(module.exports, module, module.exports, __webpack_require__);
/******/ 			threw = false;
/******/ 		} finally {
/******/ 			if(threw) delete installedModules[moduleId];
/******/ 		}
/******/
/******/ 		// Flag the module as loaded
/******/ 		module.l = true;
/******/
/******/ 		// Return the exports of the module
/******/ 		return module.exports;
/******/ 	}
/******/
/******/
/******/ 	__webpack_require__.ab = __dirname + "/";
/******/
/******/ 	// the startup function
/******/ 	function startup() {
/******/ 		// Load entry module and return exports
/******/ 		return __webpack_require__(305);
/******/ 	};
/******/
/******/ 	// run startup
/******/ 	return startup();
/******/ })
/************************************************************************/
/******/ ({

/***/ 305:
/***/ (function(__unusedmodule, __unusedexports, __webpack_require__) {

const fs = __webpack_require__(747)
const core = __webpack_require__(871)
const command = __webpack_require__(457)

async function main() {
  const workspacePath = process.env.GITHUB_WORKSPACE
  const errorFilename = `${workspacePath}/errors.txt`

  try {

    if (fs.existsSync(errorFilename)) {
      let lines = fs.readFileSync(errorFilename).toString('utf8')
      command.issueCommand('error', undefined, lines)
    }
    else {
      core.info(`No ${errorFilename} present.  Skipping!`)
    }
  } 
  catch (error) {
    core.setFailed(`Action failed with error ${error}`)
  }

}

main()


/***/ }),

/***/ 457:
/***/ (function(module) {

module.exports = eval("require")("@actions/core/lib/command");


/***/ }),

/***/ 747:
/***/ (function(module) {

module.exports = require("fs");

/***/ }),

/***/ 871:
/***/ (function(module) {

module.exports = eval("require")("@actions/core");


/***/ })

/******/ });