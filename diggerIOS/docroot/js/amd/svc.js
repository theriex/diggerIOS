/*global app, jt */
/*jslint browser, white, long, unordered */

//Server communications for IOS platform
app.svc = (function () {
    "use strict";

    var mgrs = {};  //general container for managers

    //Media Playback manager handles transport and playback calls
    mgrs.mp = (function () {
        function sendPlaybackState (stat) {
            if(stat.path) {  //add ti to enhance log tracing
                const song = app.pdat.songsDict()[stat.path];
                if(song) {
                    stat.ti = song.ti; } }
            app.player.dispatch("uiu", "receivePlaybackStatus", stat); }
        function platRequestPlaybackStatus () {
            mgrs.ios.call("statusSync", "", sendPlaybackState); }
        function platPlaySongQueue (pwsid, sq) {
            app.util.updateSongLpPcPd(sq[0].path);
            //play first, then write digdat, otherwise digdat listeners will
            //be reacting to playback that hasn't started yet.
            const paths = sq.map((s) => s.path);
            mgrs.ios.call("startPlayback", paths, function (stat) {
                sendPlaybackState(stat);
                app.pdat.writeDigDat(pwsid); }); }
    return {
        //player.plui pbco interface functions:
        requestPlaybackStatus: platRequestPlaybackStatus,
        playSongQueue: platPlaySongQueue,
        pause: function () {
            mgrs.ios.call("pausePlayback", "", function (stat) {
                stat.state = "paused";  //actual state change lags
                sendPlaybackState(stat); }); },
        resume: function () {
            mgrs.ios.call("resumePlayback", "", function (stat) {
                stat.state = "playing";  //actual state change lags
                sendPlaybackState(stat); }); },
        seek: function (ms) {
            mgrs.ios.call("seekToOffset", String(ms), function (stat) {
                stat.pos = ms;  //in case state update lags
                sendPlaybackState(stat); }); },
        //player initialization
        beginTransportInterface: function () {
            app.player.dispatch("uiu", "requestPlaybackStatus", "mp.start",
                function (status) {
                    if(status.path) {  //app init found this song playing
                        const song = app.pdat.songsDict()[status.path];
                        app.player.notifySongChanged(song, status.state); }
                    else {  //not already playing
                        jt.log("mp.beginTransport no playing song"); } }); }
    };  //end mgrs.mp returned functions
    }());


    //Copy export manager handles playlist creation.  No file copying.
    mgrs.cpx = (function () {
    return {
        exportSongs: function (/*dat, statusfunc, contfunc, errfunc*/) {
            jt.log("svc.cpx.exportSongs not supported."); }
    };  //end mgrs.cpx returned functions
    }());


    //Local manager handles local environment interaction
    mgrs.loc = (function () {
        var dls = null;  //data load state
        function parseAudioSummary (dais) {
            dais = dais.filter((d) => d.title && d.path);  //title and path req
            dais.forEach(function (dai) {
                dai.artist = dai.artist || "Unknown";
                dai.album = dai.album || "Singles"; });
            return dais; }
        function checkIfPlayed (song, dai) {
            //The iOS system music player may update the lp significantly
            //after the song has started playing, changing pd:"played" to
            //"iosqueue".  If a song is skipped, the hope is iOS will not
            //update the lp, so pd:"skipped" will be preserved, but nothing
            //is guaranteed.  User can switch players anytime so the only
            //reliable info is from the dai.
            if(dai.lp && dai.lp > song.lp) {  //lp updated by iOS
                song.lp = dai.lp;
                song.pc = dai.pc;  //also updated by iOS
                //Logging this every time the app first reads all media files
                //pushes the other startup log details off the top.
                //jt.log("Updated lp/pc for " + mgrs.lqm.readablePath(song));
                song.pd = "iosqueue"; } }
        function mergeAudioData (dais) {
            const logpre = "svc.loc.mergeAudioData ";
            dais = parseAudioSummary(dais);
            if(!dais.length) {
                return jt.log(logpre + "no audio data to merge"); }
            const dbo = dls.dbo;
            Object.values(dbo.songs).forEach(function (s) {  //mark all deleted
                s.fq = s.fq || "N";
                if(!s.fq.startsWith("D")) {
                    s.fq = "D" + s.fq; } });
            dbo.songcount = dais.length;
            dais.forEach(function (dai) {
                var song = dbo.songs[dai.path];
                if(!song) {
                    dbo.songs[dai.path] = {};
                    song = dbo.songs[dai.path]; }
                song.path = dai.path;
                song.fq = song.fq || "N";
                if(song.fq.startsWith("D")) {  //previously marked as deleted
                    song.fq = song.fq.slice(1); }  //remove deleted marker
                song.ti = dai.title;
                song.ar = dai.artist;
                song.ab = dai.album;
                song.genrejson = JSON.stringify(dai.genre);
                song.mddn = dai.mddn;
                song.mdtn = dai.mdtn;
                app.top.dispatch("dbc", "verifySong", song);
                checkIfPlayed(song, dai); });
            jt.log("svc.loc.mergeAudioData merged " + dais.length + " songs"); }
    return {
        readConfig: function (contf/*, errf*/) {
            mgrs.ios.call("readConfig", null, function (cfg) {
                if(!cfg) {
                    jt.log("svc.loc.readConfig no cfg returned, set to {}")
                    cfg = {}; }
                contf(cfg); }); },
        readDigDat: function (contfunc, errfunc) {
            dls = {dbo:{}, contf:contfunc, errf:errfunc};
            mgrs.ios.call("readDigDat", null, function (dd) {
                if(dd) {  //found something to read, not ""
                    dls.dbo = dd; }
                dls.dbo.version = mgrs.gen.plat("appversion");
                dls.dbo.songs = dls.dbo.songs || {};
                jt.log("readDigDat " + Object.keys(dls.dbo.songs).length +
                       " songs.");
                mgrs.ios.call("requestMediaRead", null, function (dais) {
                    jt.log("merging audio data for " + dais.length +
                           " songs into dls.dbo");
                    mergeAudioData(dais);
                    dls.contf(dls.dbo); }); }); },
        writeConfig: function (config, ignore/*optobj*/, contf/*, errf*/) {
            const pjson = JSON.stringify(config, null, 2);  //readable file
            mgrs.ios.call("writeConfig", pjson, contf); },
        writeDigDat: function (dbo, ignore/*optobj*/, contf/*, errf*/) {
            const datstr = JSON.stringify(dbo, null, 2);
            mgrs.ios.call("writeDigDat", datstr, contf); },
        audioDataAvailable: function () {
            const logpre = "svc.loc.audioDataAvailable ";
            jt.log(logpre + "refetching audio data");
            mgrs.ios.call("requestMediaRead", null, function (dais) {
                jt.log(logpre + "received data for " + dais.length + " songs");
                dls.dbo = app.pdat.dbObj();  //reset to latest app data
                mergeAudioData(dais);
                app.pdat.writeDigDat("svc.loc.updateAudioData"); }); }
    };  //end mgrs.loc returned functions
    }());


    //log queue parameter improves logged message content for readability.
    mgrs.lqm = (function () {
        function logformat (mobj, fixedDetail) {
            const mes = [mobj.qname, mobj.msgnum, mobj.fname, fixedDetail];
            return mes.join(":"); }
        function improveWriteConfigSend (mobj) {
            var itxt = "";
            const detobj = JSON.parse(mobj.det);  //caller serialized
            if(detobj && detobj.acctsinfo && detobj.acctsinfo.currid) {
                const acct = detobj.acctsinfo.accts.find((acc) =>
                    acc.dsId === detobj.acctsinfo.currid);
                if(acct && acct.settings && acct.settings.ctrls) {
                    const settingsJSON = JSON.stringify(acct.settings.ctrls);
                    itxt = "settings:" + settingsJSON; } }
            return logformat(mobj, itxt); }
        function improveWriteDigDat (mobj) {
            var itxt = "";
            var detobj = mobj.det;
            if(typeof detobj === "string") {
                detobj = JSON.parse(mobj.det); } //caller serialized
            if(detobj.songs) {
                itxt = " " + Object.keys(detobj.songs).length + " songs."; }
            return logformat(mobj, itxt); }
        function improveStatusSync (mobj) {
            var itxt = "";
            if(mobj.det) {  //return from call has details object
                if(mobj.det.path && app.pdat.dbObj()) {
                    const sd = app.pdat.songsDict();
                    if(sd) {
                        const song = sd[mobj.det.path];
                        if(song) {
                            mobj.det.ti = song.ti;
                    itxt = JSON.stringify(mobj.det); } } } }
            return logformat(mobj, itxt); }
        function improveSpecificMessage (io, mobj) {
            var itxt = "";
            switch(mobj.fname) {
            case "writeConfig":
                if(io === "snd") {
                    itxt = improveWriteConfigSend(mobj); }
                break;
            case "writeDigDat":
                itxt = improveWriteDigDat(mobj);
                break;
            case "statusSync":
                itxt = improveStatusSync(mobj);
                break; }
            return itxt; }
        function improveLogText (io, mstr, mobj) {
            var itxt = "";
            try {
                itxt = improveSpecificMessage(io, mobj);
            } catch(e) {
                jt.log("lqm.improveSpecificMessage failed: " + e); }
            if(!itxt) {
                itxt = mstr;
                if(itxt.length > 250) {
                    itxt = itxt.slice(0, 150) + "..." + itxt.slice(-50); } }
            return itxt; }
    return {
        readablePath: function (sgi) {
            return (sgi.path.slice(sgi.path.indexOf("?") + 4) +
                    " \"" + jt.ellipsis(sgi.ti, 20) + "\""); },
        //mobj fields: qname, msgnum, fname, det
        improveSendLogTxt: function (mstr, mobj) {
            return improveLogText("snd", mstr, mobj); },
        improveReturnLogTxt: function (mstr, mobj) {
            return improveLogText("rcv", mstr, mobj); }
    };  //end mgrs.lqm returned functions
    }());


    //ios manager handles calls between js and ios.  All calls are across
    //separate processes with no synchronous support, so calls are queued to
    //avoid unintuitive sequencing, deadlock, starvation etc.  Standard API
    //calls are expected to be nearly instant, but it is possible something
    //might take a few seconds when the app is first spinning up.  Reading
    //the song library is also typically very fast, but the app can handle
    //that taking longer without looking crashed.  Hub calls can take random
    //amounts of time so each call type gets its own queue.
    mgrs.ios = (function () {
        const qs = {"main":{q:[], cc:0, maxlag:10 * 1000},   //API calls
                    "srdr":{q:[], cc:0, maxlag:25 * 1000}};  //song lib read
        function qnameForFunc (iosFuncName) {
            if(iosFuncName === "requestMediaRead") {
                return "srdr"; }
            if(iosFuncName.startsWith("hub")) {
                if(!qs[iosFuncName]) {
                    qs[iosFuncName] = {q:[], cc:0, maxlag:30 * 1000}; }
                return iosFuncName; }
            return "main"; }
        function callIOS (queueName, mqo) {
            var param = mqo.pobj || "";
            if(param && typeof param === "object") {  //object or array
                param = JSON.stringify(param); }
            const mes = [queueName, mqo.msgnum, mqo.fname, param];
            const msg = mes.join(":");
            jt.log("callIOS:" + mgrs.lqm.improveSendLogTxt(
                msg, {qname:queueName, msgnum:mqo.msgnum, fname:mqo.fname,
                      det:mqo.pobj || ""}));
            window.webkit.messageHandlers.diggerMsgHandler.postMessage(msg); }
        function readSerializedObject(txt) {
            var oei = 1;
            var cnt = 1;
            var esc = false;
            var inq = false;
            var ch = "";
            while(txt && oei < txt.length && cnt) {
                ch = txt.charAt(oei);
                if(ch === "\\" && !esc) {
                    esc = true; }
                else if(!esc) {  //not an escaped char
                    if(ch === "\"") {
                        inq = !inq; }
                    else if(!inq) {  //not part of a string
                        if(ch === "{") { cnt += 1; }
                        if(ch === "}") { cnt -= 1; } } }
                oei += 1; }
            return txt.slice(0, oei); }
        function readSerializedObjectsCSV (txt) {
            var res = []; var obj;
            while(txt) {
                obj = readSerializedObject(txt);
                res.push(obj);
                txt = txt.slice(obj.length);
                if(txt.startsWith(",")) {
                    txt = txt.slice(1).trim(); } }
            return res; }
        function analyzeJSON (txt) {
            if(txt.startsWith("[") && txt.endsWith("]")) {
                jt.log("analyzeJSON txt is an array: '['...']'");
                const objs = readSerializedObjectsCSV(txt.slice(1, -1));
                jt.log("analyzeJSON found " + objs.length + " objs");
                objs.forEach(function (obj, idx) {
                    try {
                        JSON.parse(obj);
                    } catch(e) {
                        jt.log("obj[" + idx + "] " + e);
                        jt.log(obj); } }); } }
        function unhandledError (code, errtxt) {
            jt.log("Default error handler code: " + code +
                   ", errtxt: " + errtxt); }
        function parseMessageText(mstr) {
            var res = "";
            const [qnm, msgid, fnm, ...msgtxt] = mstr.split(":");
            res = msgtxt.join(":");
            if(res && (res.startsWith("{") || res.startsWith("["))) {
                try {
                    res = JSON.parse(res);
                } catch(e) {
                    //dump full string to console so it can be debug viewed
                    jt.log("svc.ios.retv parse err " + e + " JSON res: " + res);
                    analyzeJSON(res);
                    res = "Error - parseMessageText failed " + e;
                } }
            const mobj = {qname:qnm, msgnum:msgid, fname:fnm, det:res};
            jt.log("ios.retv:" + mgrs.lqm.improveReturnLogTxt(mstr, mobj));
            return mobj; }
        function parseErrorText (rmo) {
            var errmsg = rmo.det;
            const emprefix = "Error - ";
            errmsg = errmsg.slice(emprefix.length);
            const codeprefix = "code: ";
            if(errmsg.indexOf(codeprefix) >= 0) {
                errmsg = errmsg.slice(codeprefix.length);
                rmo.errcode = parseInt(errmsg, 10) || 0;
                if(errmsg.indexOf(" ") >= 0) {
                    errmsg = errmsg.slice(errmsg.indexOf(" ")); } }
            else {
                rmo.errcode = 0; }
            rmo.errmsg = errmsg; }
        function handlePushMessage(rmo) {
            jt.log("svc.ios.handlePushMessage " +
                   jt.ellipsis(JSON.stringify(rmo), 300));
            if(rmo.fname === "initMediaInfo") {
                const dais = JSON.parse(JSON.stringify(rmo.det));
                mgrs.loc.audioDataAvailable(); } }
        function verifyQueueMatch(rmo) {
            if(rmo.qname === "iospush") {
                handlePushMessage(rmo);
                return false; }  //no corresponding queue
            if(!qs[rmo.qname].q.length) {
                jt.log("ios.retv no pending mssages in queue " + rmo.qname +
                       ". Ignoring " + jt.ellipsis(JSON.stringify(rmo), 300));
                return false; }
            if(qs[rmo.qname].q[0].fname !== rmo.fname) {
                jt.log("ios.retv queue " + rmo.qname + " expected fname " +
                       qs[rmo.qname].q[0].fname + " but received " +
                       rmo.fname + ". Ignoring.");
                return false; }
            const expmid = qs[rmo.qname].q[0].msgnum;
            const rcvmid = parseInt(rmo.msgnum, 10);
            if(expmid !== rcvmid) {
                jt.log("ios.retv queue " + rmo.qname + " fname " + rmo.fname +
                       " expected msgid " + expmid + " but received " +
                       rcvmid + ". Continuing despite sequence error.");
                return true; }
            return true; }
    return {
        call: function (iosFuncName, paramObj, callback, errorf) {
            var cruft = null;
            const qname = qnameForFunc(iosFuncName);
            paramObj = paramObj || "";
            qs[qname].cc += 1;
            qs[qname].q.push({fname:iosFuncName, pobj:paramObj, cbf:callback,
                              errf:errorf || unhandledError,
                              msgnum:qs[qname].cc, ts:Date.now()});
            if(qs[qname].q.length === 1) {
                callIOS(qname, qs[qname].q[0]); }
            else {  //multiple calls in queue, clear cruft and resume if needed
                while(Date.now - qs[qname].q[0].ts > qs[qname].maxlag) {
                    cruft = qs[qname].q.shift();
                    jt.log("ios call cleared crufty " + cruft.fname + " " +
                           jt.ellipsis(JSON.stringify(cruft.pobj), 300)); }
                if(cruft) {  //restart the queue
                    callIOS(qname, qs[qname].q[0]); } } },
        retv: function (mstr) {
            const rmo = parseMessageText(mstr);
            if(!verifyQueueMatch(rmo)) {  //failure message logged
                return; }
            if(typeof rmo.det === "string" && rmo.det.startsWith("Error - ")) {
                parseErrorText(rmo); }
            const mqo = qs[rmo.qname].q[0];  //current message ref
            try {
                if(rmo.errmsg) {
                    mqo.errf(rmo.errcode, rmo.errmsg); }
                else {  //send a modifiable deep copy of results for use by cbf
                    mqo.cbf(JSON.parse(JSON.stringify(rmo.det))); }
            } catch(e) {
                jt.log("ios.retv " + rmo.qname + " " + rmo.msgnum + " " +
                       rmo.fname + " " +(rmo.errmsg? "error" : "success") +
                       " callback failed: " + e + "  stack: " + e.stack);
            }
            qs[rmo.qname].q.shift();  //done processing returned message
            if(qs[rmo.qname].q.length) {  //process next in queue
                setTimeout(function () {  //on a new process stack for isolation
                    callIOS(rmo.qname, qs[rmo.qname].q[0]); }, 50); } }
    };  //end mgrs.ios returned functions
    }());


    //general manager is main interface for app logic
    mgrs.gen = (function () {
        var platconf = {
            hdm: "loc",   //host data manager is local
            musicPath: "fixed",  //can't change where music files are
            dbPath: "fixed",  //rating info is only kept in app files for now
            urlOpenSupp: false,  //opening a tab breaks webview
            defaultCollectionStyle: "",   //not permanentCollection
            audsrc: "IOS",
            appversion: "",
            versioncode: ""};
    return {
        initialize: function () {  //don't block init of rest of modules
            mgrs.ios.call("getVersionCode", null, function (val) {
                platconf.versioncode = val; });
            mgrs.ios.call("getAppVersion", null, function (val) {
                platconf.appversion = val; });
            app.boot.addApresModulesInitTask("initPLUI", function () {
                app.player.dispatch("plui", "initInterface", mgrs.mp); });
            app.pdat.addApresDataNotificationTask("startPLUI", function () {
                mgrs.mp.beginTransportInterface(); });
            app.pdat.svcModuleInitialized(); },
        plat: function (key) { return platconf[key]; },
        okToPlay: function (song) {
            //no known bad file types returned from media query.
            return song; },
        passthroughHubCall: function (qname, reqnum, endpoint, verb, dat) {
            const hfn = "hubcall" + endpoint;
            const pobj = {"endpoint":endpoint,
                          url:endpoint,
                          "verb":verb,
                          "dat":dat};
            if(pobj.verb.startsWith("raw")) {
                pobj.verb = pobj.verb.slice(3); }
            const pstr = JSON.stringify(pobj);
            mgrs.ios.call(hfn, pstr,
                function (res) {
                    app.top.dispatch("hcq", "hubResponse", qname, reqnum,
                                     200, JSON.stringify(res)); },
                function (code, errdet) {
                    app.top.dispatch("hcq", "hubResponse", qname, reqnum,
                                     code, errdet); }); },
        docContent: function (docurl, contf) {
            var fn = jt.dec(docurl);
            var sidx = fn.lastIndexOf("/");
            if(sidx >= 0) {
                fn = fn.slice(sidx + 1); }
            mgrs.ios.call("docContent", "docs/" + fn, contf); },
        copyToClipboard: function (txt, contf/*, errf*/) {
            mgrs.ios.call("copyToClipboard", txt, contf); },
        tlasupp: function (act) {
            const unsupp = {
                "updversionnote":"App Store updates after server",
                "ignorefldrsbutton":"No music file folders on iOS",
                "readfilesbutton":"All media queried at app startup"};
            return (!act.id || !unsupp[act.id]); }
    };  //end mgrs.gen returned functions
    }());

return {
    init: function () { mgrs.gen.initialize(); },
    plat: function (key) { return mgrs.gen.plat(key); },
    readConfig: mgrs.loc.readConfig,
    readDigDat: mgrs.loc.readDigDat,
    writeConfig: mgrs.loc.writeConfig,
    writeDigDat: mgrs.loc.writeDigDat,
    playSongQueue: mgrs.mp.playSongQueue,
    requestPlaybackStatus: mgrs.mp.requestPlaybackStatus,
    passthroughHubCall: mgrs.gen.passthroughHubCall,
    copyToClipboard: mgrs.gen.copyToClipboard,
    okToPlay: mgrs.gen.okToPlay,
    iosReturn: function (jsonstr) { mgrs.ios.retv(jsonstr); },  //iOS callback
    docContent: function (du, cf) { mgrs.gen.docContent(du, cf); },
    topLibActionSupported: function (a) { return mgrs.gen.tlasupp(a); },
    extensionInterface: function (/*name*/) { return null; }
};  //end of returned functions
}());
