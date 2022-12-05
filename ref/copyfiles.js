/*jslint node, white */

//Copy the digger webapp src files into docroot.  The digger project must be
//available as a sibling project off the same parent directory as diggerIOS.
//
//usage:
//  node copyfiles.js
//to copy the most recent files over, or
//  node copyfiles.js delete
//to get rid of the copied files
//
//"node ref/copyfiles.js" is called as a "Run Script" build stage just
//before "Compile Sources" in the diggerIOS project.

var linker = (function () {
    "use strict";

    var fs = require("fs");
    var ws = {srcdirs:["", "css", "img", "js", "js/amd", "docs"],
              ovr:{"svc.js": "Local version to interface with phone",
                   ".DS_Store": "Mac filesystem detritus"}};


    function makeWorkingSetRoots () {
        var dn = __dirname;
        ws.lnkr = dn.slice(0, dn.lastIndexOf("/"));
        ws.digr = ws.lnkr.slice(0, ws.lnkr.lastIndexOf("/") + 1) +
            "digger/docroot/";
        ws.lnkr += "/diggerIOS/docroot/";
    }


    function jslf (obj, method, ...args) {
        return obj[method].apply(obj, args);
    }


    function checkUpToDate (hfp, dfp) {
        const hs = fs.statSync(hfp)
        const ds = fs.statSync(dfp)
        if(ds.mtime > hs.mtime) {
            fs.copyFileSync(dfp, hfp);
            console.log("updated " + hfp); }
        else {
            console.log("up2date " + hfp); }
    }


    function checkFile (cmd, relpath, fname) {
        var hfp = ws.lnkr + relpath + "/" + fname;
        var dfp = ws.digr + relpath + "/" + fname;
        if(fname.endsWith("~")) { return; }
        if(ws.ovr[fname]) { return; }
        if(!jslf(fs, "existsSync", hfp)) {
            if(cmd === "create") {
                fs.copyFileSync(dfp, hfp);
                console.log("created " + hfp); }
            else {
                console.log("missing " + hfp); } }
        else {  //file exists
            if(cmd === "delete") {
                fs.unlinkSync(hfp);
                console.log("removed " + hfp); }
            else {
                checkUpToDate(hfp, dfp); } }
    }


    function traverseLinks (cmd) {
        console.log("Command: " + cmd);
        makeWorkingSetRoots();
        console.log("Copying " + ws.digr + " files to " + ws.lnkr);
        ws.srcdirs.forEach(function (relpath) {
            var dir = ws.digr + relpath;
            var options = {encoding:"utf8", withFileTypes:true};
            fs.readdir(dir, options, function (err, dirents) {
                if(err) { throw err; }
                dirents.forEach(function (dirent) {
                    if(dirent.isFile()) {
                        checkFile(cmd, relpath, dirent.name); } }); }); });
    }


    return {
        run: function () { traverseLinks(process.argv[2] || "create"); }
    };
}());

linker.run();
