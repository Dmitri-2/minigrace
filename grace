#!/usr/bin/env node

"use strict";

var path = require("path");
var fs = require("fs");
var util = require('util');

global.minigrace = {};
global.sourceObject = null;
global.invocationCount = 0;
global.onOuter = false;
global.onSelf = false;
global.gctCache = {};
global.originalSourceLines = {};
global.stackFrames = [];

function MiniGrace() {
    this.compileError = false;
    this.vis = "standard";
    this.mode = "js";
    this.modname = "main";
    this.verbosity = 30;
    this.lastSourceCode = "";
    this.lastMode = "";
    this.lastModname = "";
    this.breakLoops = false;
    this.debugMode = false;
    this.lastDebugMode = false;
    this.printStackFrames = true;
    
    this.generated_output = "";
    
    this.stdout_write = function(value) { };
    
    this.stderr_write = function(value) {
        console.log(value);
    };
    
    this.stdin_read = function() {
        return "";
    };
}

MiniGrace.prototype.trapErrors = function(func) {
    this.exception = null;
    if (Grace_prelude.methods["while()do"])
        Grace_prelude.methods["while()do"].safe = this.breakLoops;
    try {
        func();
    } catch (e) {
        var eStr = e.toString();
        if ((eStr === "RangeError: Maximum call stack size exceeded") ||    // Chrome
            (eStr === "InternalError: too much recursion") ) {              // Firefox
            e = new GraceExceptionPacket(new GraceException("TooMuchRecursion", ProgrammingErrorObject),
                   new GraceString("Does one of your methods request execution of itself without limit?"));
        }
        if (e.exctype == 'graceexception') {
            this.exception = e;
            callmethod(e, "printBacktrace", [0]);
            if (originalSourceLines[e.moduleName]) {
                var lines = originalSourceLines[e.moduleName];
                for (let i = e.lineNumber - 1; i <= e.lineNumber + 1; i++) {
                    if (lines[i-1] != undefined) {
                        for (var j=0; j<4-i.toString().length; j++)
                            this.stderr_write(" ");
                        this.stderr_write("" + i + ": " + lines[i-1] + "\n");
                    }
                }
            }
            if (e.stackFrames.length > 0 && this.printStackFrames) {
                this.stderr_write("Stack frames:\n");
                for (i=0; i<e.stackFrames.length; i++) {
                    this.stderr_write("  " + e.stackFrames[i].methodName + "\n");
                    var stderr_write = this.stderr_write;
                    e.stackFrames[i].forEach(function(name, value) {
                        stderr_write("    " + name);
                        var debugString = "unknown";
                        try {
                            if (typeof value == "undefined") {
                                debugString = "‹undefined›";
                            } else {
                                debugString = callmethod(value,
                                    "asDebugString", [0])._value;
                            }
                        } catch(e) {
                            debugger;
                            debugString = "<[Error calling asDebugString: " +
                                  e.message._value + "]>";
                        }
                        debugString = debugString.replace("\\", "\\\\");
                        debugString = debugString.replace("\n", "\\n");
                        if (debugString.length > 60)
                            debugString = debugString.substring(0,57) + "...";
                        stderr_write(" = " + debugString + "\n");
                    });
                }
            }
        } else if (e === "SystemExit") {
            process.exit(1);
        } else {
            this.stderr_write("Internal error around line " + getLineNumber() + 
                " of " + getModuleName() + ": " + e + "\n");
            throw e;
            process.exit(2);
        }
    } finally {
        if (Grace_prelude.methods["while()do"])
            Grace_prelude.methods["while()do"].safe = false;
    }
};

MiniGrace.prototype.run = function(fileName) {
    stackFrames = [];
    var code = minigrace.generated_output;
    minigrace.stdout_write = function(value) {
        process.stdout.write(value, "utf-8");
    };
    minigrace.stderr_write = function(value) {
        process.stderr.write(value, "utf-8");
    };
    minigrace.stdin_read = function() {
        return "";
    };
    var modName = path.basename(fileName, ".js");
    var dirName = path.dirname(fileName);
    this.loadModule(modName, dirName);
        // defines a global gracecode_‹modName›
    var theModule = global[graceModuleName(modName)];
    this.trapErrors(function() {
        do_import(fileName, theModule);
    }              );
};

//  This method has been added to the ECMAScript 6 specification, but is not yet in node:

if ( ! String.prototype.endsWith) {
    String.prototype.endsWith = function (suffix, position) {
        if (position === undefined || position > this.length) {
            position = this.length;
        }
        position = position - suffix.length;
        var lastIndex = this.lastIndexOf(suffix, position);
        return lastIndex !== -1 && lastIndex === position;
    };
}

function graceModuleName(fileName) {
    var prefix = "gracecode_";
    var base = path.basename(fileName, ".js");
    return prefix + escapeident(base);
}

function escapeident(id) {
    // must correspond to escapeident(_) in genjs.grace
    var nm = "";
    for (var ix = 0; ix < id.length; ix++) {
        var o = id.charCodeAt(ix);
        if (((o >= 97) && (o <= 122)) || ((o >= 65) && (o <= 90)) ||
            ((o >= 48) && (o <= 57))) {
            nm = nm + id.charAt(ix);
        } else {
            nm = nm + "__" + o + "__";
        }
    }
    return nm;
}

function findOnPath(fn, pathArray) {
    if (fn[0] === "/") {
        if (fs.existsSync(fn)) { return fn; }
        throw new Error('file "' + fn + '" does not exist.');
    }
    var candidates = [];
    for (var ix = 0; ix < pathArray.length ; ix++) {
        var candidate = path.resolve(pathArray[ix], fn);  
            // path.resolve joins, normalizes, & makes absolute
        if (fs.existsSync(candidate)) { return candidate; }
        candidates.push(candidate);
    }
    console.error('module "' + fn + '" not found.  Tried:');
    for (ix = 0; ix < candidates.length ; ix++) {
        console.error(candidates[ix]);
    }
    process.exit(2);
    return "undefined";
}

function addToPathIfNecessary(dir) {
    if ( pathdirs.indexOf(dir) === -1 ) {
        pathdirs.push(dir);
    }
}

var graceModulePath = process.env.GRACE_MODULE_PATH;
if (graceModulePath === undefined) {
    var fallbackPath = "/usr/local/lib/grace/modules/";
    try {
        if (fs.statSync(fallbackPath).isDirectory) {
            graceModulePath = fallbackPath;
        }
    } catch (e) {
            graceModulePath = "";
    }
    if (! process.env.CI) {
        console.warn("environment does not contain GRACE_MODULE_PATH; using " + graceModulePath);
    }
}

var pathdirs = graceModulePath.split(path.delimiter);

addToPathIfNecessary("./");
addToPathIfNecessary("../");

MiniGrace.prototype.loadModule = function(moduleName, referencingDir) {
    var graceModule = graceModuleName(moduleName);
    if (typeof global[graceModule] === 'function') return;   //already loaded
    var extn = ".js";
    var fileName = moduleName;
    if ( moduleName.endsWith(extn)) {
        moduleName = moduleName.substring(0, moduleName.length - extn.length);
    } else {
        fileName = fileName + extn;
    }
    var found = findOnPath(fileName, [referencingDir].concat(pathdirs));
    var sourceDir = path.dirname(fs.realpathSync(found));
    try {
        require(found);
    } catch (e) {
        console.warn("%s while loading file %s", e.toString(), found);
        process.exit(-3);
    }
    if (typeof global[graceModule] !== 'function') {
        console.error("loaded file '" + found + "', but it did not define '" +
                            graceModule + "'.");
        console.error('loadModule(' + moduleName + ', ' +
                            referencingDir + ') failed!');
        process.exit(2);
    }
    var recursiveImports = global[graceModule].imports;
    for (var ix = 0; ix < recursiveImports.length; ix++) {
        MiniGrace.prototype.loadModule(recursiveImports[ix], sourceDir);
    }
};

function abspath(file) {
    if (path.isAbsolute(file)) return file;
    return path.join(process.cwd(), file);
}

try {
    require(findOnPath("gracelib.js", pathdirs));
    require(findOnPath("unicodedata.js", pathdirs));
    minigrace = new MiniGrace();
    minigrace.loadModule("standardGrace", "./");
    var executable = process.argv[2];
    minigrace.execFile = abspath(executable);

    minigrace.trapErrors(function() {
        // as as special case, do_import("standardGrace", …) adds to Grace_prelude,
        // rather than creating a new module object.
        do_import('standardGrace', gracecode_standardGrace);
        minigrace.run(executable);
    });
} catch (e) {
    if (typeof e.message === "string")
        console.error(e.message)
    else if (typeof e.message._value === "string")
        console.error(e.message._value)
    else console.error(e.message);
    console.error(e.exitStack);
    process.exit(1);
}

if (typeof global !== "undefined") {
    global.path = path;
}
