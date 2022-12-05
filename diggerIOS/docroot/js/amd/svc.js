/*global app, jt, Android, console */
/*jslint browser, white, long, unordered */

//Server communications for IOS platform
app.svc = (function () {
    "use strict";

    var mgrs = {};  //general container for managers

    //Local manager handles local environment interaction
    mgrs.loc = (function () {
        var config = null;
        // var dbo = null;
    return {
        getConfig: function () { return config; },
        loadInitialData: function () {
            jt.log("loadInitialData not implemented yet"); }
    };  //end mgrs.loc returned functions
    }());


    //ios manager handles calls between js and ios.  All calls are across
    //separate processes with no synchronous support, so queue calls to avoid
    //unintuitive sequencing, deadlock, starvation etc.
    mgrs.ios = (function () {
        const qs = {"main":{q:[], maxlag:10 * 1000},
                    "hubc":{q:[], maxlag:30 * 1000}};
        function callIOS (queueName, mqo) {
            const msg = JSON.stringify({qname:queueName, fname:mqo.fname,
                                        pobj:mqo.pobj});
            jt.log("callIOS: " + msg);
            window.webkit.messageHandlers.diggerMsgHandler.postMessage(msg); }
    return {
        call: function (iosFuncName, paramObj, callback, qname) {
            qname = qname || "main";
            paramObj = paramObj || "";
            qs[qname].q.push({fname:iosFuncName, pobj:paramObj, cbf:callback,
                              ts:Date.now()});
            if(qs[qname].q.length === 1) {
                callIOS(qname, qs[qname].q[0]); }
            else {  //multiple calls in queue, clear cruft and resume if needed
                while(Date.now - qs[qname].q[0].ts > qs[qname].maxlag) {
                    const mqo = qs[qname].q.shift();
                    jt.log("ios call cleared crufty " + mqo.fname + " " +
                           jt.ellipsis(JSON.stringify(mqo.pobj), 300)); }
                callIOS(qname, qs[qname].q[0]); } },
        return: function (jsonstr) {
            const res = JSON.parse(jsonstr);
            if(qs[res.qname].q[0].fname === res.fname) {  //normal return
                const mqo = qs[res.qname].q.shift();
                jt.log("iosReturn callback " + res.qname + " "  + res.fname +
                       " " + jt.ellipsis(jsonstr, 300));
                mqo.cbf(res.result); }
            else {  //mismatched return for current queue (previous timeout)
                jt.log("iosReturn no match current queue entry, ignoring " +
                       res.qname + " " + res.fname); } }
    };  //end mgrs.ios returned functions
    }());


    //general manager is main interface for app logic
    mgrs.gen = (function () {
        var platconf = {
            hdm: "loc",   //host data manager is local
            musicPath: "fixed",  //can't change where music files are
            dbPath: "fixed",  //rating info is only kept in app files for now
            audsrc: "IOS",
            versioncode: ""};
    return {
        plat: function (key) { return platconf[key]; },
        initialize: function () {  //don't block init of rest of modules
            setTimeout(mgrs.loc.loadInitialData, 50);
            mgrs.ios.call("getVersionCode", null, function (val) {
                platconf.versioncode = val; }); }
    };  //end mgrs.gen returned functions
    }());

return {
    init: function () { mgrs.gen.initialize(); },
    iosReturn: function (jsonstr) { mgrs.ios.return(jsonstr); },
    plat: function (key) { return mgrs.gen.plat(key); },
    dispatch: function (mgrname, fname, ...args) {
        try {
            return mgrs[mgrname][fname].apply(app.svc, args);
        } catch(e) {
            console.log("top.dispatch: " + mgrname + "." + fname + " " + e +
                        " " + new Error("stack trace").stack);
        } }
};  //end of returned functions
}());
