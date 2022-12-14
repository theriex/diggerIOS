/*global app, jt, Android, console */
/*jslint browser, white, long, unordered */

//Server communications for IOS platform
app.svc = (function () {
    "use strict";

    var mgrs = {};  //general container for managers

    //song database processing
    mgrs.sg = (function () {
        var dbstatdiv = "topdlgdiv";
        var apresloadcmd = "";
        function parseAudioSummary (dais) {
            jt.out(dbstatdiv, "Parsing audio summary...");
            dais = dais.filter((d) => d.title && d.path);  //title and path req
            dais.forEach(function (dai) {
                dai.artist = dai.artist || "Unknown";
                dai.album = dai.album || "Singles"; });
            return dais; }
        function setArtistFromPath (song) {
            const pes = song.path.split("/");
            song.ti = pes[pes.length - 1];
            if(pes.length >= 3) {
                song.ar = pes[pes.length - 3];
                song.ab = pes[pes.length - 2]; }
            else if(pes.length >= 2) {
                song.ar = pes[pes.length - 2]; } }
        function mergeAudioData (dais) {
            dais = parseAudioSummary(dais);
            jt.out(dbstatdiv, "Merging Digger data...");
            const dbo = mgrs.loc.getDatabase();
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
                if(song.fq.startsWith("D")) {
                    song.fq = song.fq.slice(1); }
                song.ti = dai.title;
                song.ar = dai.artist;
                song.ab = dai.album;
                app.top.dispatch("dbc", "verifySong", song);
                if(!song.ar) {  //artist required for hub sync
                    setArtistFromPath(song); } }); }
    return {
        verifyDatabase: function (dbo) {
            var stat = app.top.dispatch("dbc", "verifyDatabase", dbo);
            if(stat.verified) { return dbo; }
            jt.log("svc.db.verifyDatabase re-initializing dbo, received " +
                   JSON.stringify(stat));
            dbo = {version:mgrs.gen.plat("appversion"),
                   scanned:"",  //ISO latest walk of song files
                   songcount:0,
                   //songs are indexed by relative path off of musicPath e.g.
                   //"artistFolder/albumFolder/disc#?/songFile"
                   songs:{}};
            return dbo; },
        loadLibrary: function (procdivid, apresload) {
            dbstatdiv = procdivid || "topdlgdiv";
            apresloadcmd = apresload || "";
            mgrs.ios.call("requestMediaRead", null, function (dais) {
                mergeAudioData(dais); }, "srdr"); }
    };  //end mgrs.sg returned functions
    }());


    //Local manager handles local environment interaction
    mgrs.loc = (function () {
        var config = null;
        var dbo = null;
        function failsafeJSONParse (jstr, dflt, fname) {
            var val = null;
            jstr = jstr || dflt;
            fname = fname || "";
            try {
                val = JSON.parse(jstr);
            } catch(e) {
                jt.err(fname + " JSON read failed: " + e);
            }
            return val; }
    return {
        getConfig: function () { return config; },
        getDigDat: function () { return dbo; },
        loadInitialData: function () {
            mgrs.ios.call("readConfig", null, function (cj) {
                config = failsafeJSONParse(cj, "{}", "readConfig");
                mgrs.ios.call("readDigDat", null, function (dj) {
                    dbo = failsafeJSONParse(dj, "{}", "readDigDat");
                    config = config || {};  //default account set up in top.js
                    dbo = mgrs.sg.verifyDatabase(dbo);
                    //let rest of app know data is ready, then check library:
                    const startdata = {"config":config, songdata:dbo};
                    const uims = ["top",      //display login name
                                  "filter"];  //show settings, app.deck.update
                    uims.forEach(function (uim) {
                        app[uim].initialDataLoaded(startdata); });
                    if(!dbo.scanned) {
                        setTimeout(mgrs.sg.loadLibrary, 50); } }); }); },
        loadDigDat: function (cbf) {
            mgrs.ios.call("readDigDat", null, function (dj) {
                dbo = failsafeJSONParse(dj, "{}", "readDigDat");
                dbo = mgrs.sg.verifyDatabase(dbo);
                cbf(dbo); }); },
        noteUpdatedState: function (/*label*/) {
            //If label === "deck" and the IOS platform needs to keep info
            //outside the app UI, this is the place to update that data
            return; },
        fetchSongs: function (contf/*, errf*/) {  //call stack as if web call
            setTimeout(function () { contf(dbo.songs); }, 50); }
    };  //end mgrs.loc returned functions
    }());


    //ios manager handles calls between js and ios.  All calls are across
    //separate processes with no synchronous support, so queue calls to avoid
    //unintuitive sequencing, deadlock, starvation etc.
    mgrs.ios = (function () {
        const qs = {"main":{q:[], cc:0, maxlag:10 * 1000},
                    "srdr":{q:[], cc:0, maxlag:25 * 1000},
                    "hubc":{q:[], cc:0, maxlag:30 * 1000}};
        function callIOS (queueName, mqo) {
            var param = mqo.pobj || "";
            if(param && typeof param === "object") {  //object or array
                param = JSON.stringify(param); }
            const msg = (queueName + ":" + mqo.msgnum + ":" + mqo.fname + ":" +
                         param);
            jt.log("callIOS: " + msg);
            window.webkit.messageHandlers.diggerMsgHandler.postMessage(msg); }
    return {
        call: function (iosFuncName, paramObj, callback, qname) {
            var cruft = null;
            qname = qname || "main";
            paramObj = paramObj || "";
            qs[qname].cc += 1;
            qs[qname].q.push({fname:iosFuncName, pobj:paramObj, cbf:callback,
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
            var result = "";
            const qname = mstr.slice(0, mstr.indexOf(":"));
            mstr = mstr.slice(mstr.indexOf(":") + 1);
            const msgid = mstr.slice(0, mstr.indexOf(":"));
            mstr = mstr.slice(mstr.indexOf(":") + 1);
            const fname = mstr.slice(0, mstr.indexOf(":"));
            mstr = mstr.slice(mstr.indexOf(":") + 1);
            result = mstr;
            if(mstr && (mstr.startsWith("{") || mstr.startsWith("["))) {
                result = JSON.parse(mstr); }
            const logtxt = (qname + " " + msgid + " " + fname + " " +
                            jt.ellipsis(mstr, 300));
            if(!qs[qname].q.length) {
                jt.log("ios.retv ignoring spurious return: " + logtxt); }
            else if(qs[qname].q[0].fname === fname) {  //return value for call
                const mqo = qs[qname].q.shift();
                jt.log("iosReturn callback: " + logtxt);
                if(!mstr.startsWith("Error -")) {
                    try {
                        mqo.cbf(result);
                    } catch(e) {
                        jt.log("svc.ios.return callback failed: " + e);
                    } }
                if(qs[qname].q.length) {  //process next in queue
                    callIOS(qname, qs[qname].q[0]); } }
            else {  //mismatched return for current queue (previous timeout)
                jt.log("iosReturn no match current queue entry, ignoring " +
                       logtxt); } }
    };  //end mgrs.ios returned functions
    }());


    //general manager is main interface for app logic
    mgrs.gen = (function () {
        var platconf = {
            hdm: "loc",   //host data manager is local
            musicPath: "fixed",  //can't change where music files are
            dbPath: "fixed",  //rating info is only kept in app files for now
            audsrc: "IOS",
            appversion: "",
            versioncode: ""};
    return {
        plat: function (key) { return platconf[key]; },
        initialize: function () {  //don't block init of rest of modules
            setTimeout(mgrs.loc.loadInitialData, 50);
            mgrs.ios.call("getVersionCode", null, function (val) {
                platconf.versioncode = val; });
            mgrs.ios.call("getAppVersion", null, function (val) {
                platconf.appversion = val; }); }
    };  //end mgrs.gen returned functions
    }());

return {
    init: function () { mgrs.gen.initialize(); },
    plat: function (key) { return mgrs.gen.plat(key); },
    iosReturn: function (jsonstr) { mgrs.ios.retv(jsonstr); },
    loadDigDat: function (cbf) { mgrs.loc.loadDigDat(cbf); },
    songs: function () { return mgrs.loc.getDigDat().songs; },
    fetchSongs: function (cf, ef) { mgrs.loc.fetchSongs(cf, ef); },
    noteUpdatedState: function (label) { mgrs.loc.noteUpdatedState(label); },
    dispatch: function (mgrname, fname, ...args) {
        try {
            return mgrs[mgrname][fname].apply(app.svc, args);
        } catch(e) {
            console.log("top.dispatch: " + mgrname + "." + fname + " " + e +
                        " " + new Error("stack trace").stack);
        } }
};  //end of returned functions
}());
