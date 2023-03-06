/*global app, jt, Android, console */
/*jslint browser, white, long, unordered */

//Server communications for IOS platform
app.svc = (function () {
    "use strict";

    var mgrs = {};  //general container for managers


    //Screenshot manager returns demo data for simulator UI displays
    mgrs.scr = (function () {
        var active = false;  //true if stubbed returns demo data
        const dummyStatus = {state:"paused", pos:12*1000, dur:210*1000,
                             path:"SongU.mp3"};  //oldest
        const kwdefs = {Social: {pos: 1, sc: 0, ig: 0, dsc: ""},
                        Personal: {pos: 0, sc: 0, ig: 0, dsc: ""},
                        Office: {pos: 4, sc: 0, ig: 0, dsc: ""},
                        Dance: {pos: 2, sc: 0, ig: 0, dsc: ""},
                        Ambient: {pos: 3, sc: 0, ig: 0, dsc: ""},
                        Jazz: {pos: 0, sc: 0, ig: 0, dsc: ""},
                        Classical: {pos: 0, sc: 0, ig: 0, dsc: ""},
                        Talk: {pos: 0, sc: 0, ig: 0, dsc: ""},
                        Solstice: {pos: 0, sc: 0, ig: 0, dsc: ""}};
        const settings = {
            "ctrls": [{"tp": "range", "c": "al", "x": 27, "y": 62},
                      {"tp": "range", "c": "el", "x": 49, "y": 47},
                      {"tp": "kwbt", "k": "Social", "v": "pos"},
                      {"tp": "kwbt", "k": "Dance", "v": "off"},
                      {"tp": "kwbt", "k": "Ambient", "v": "neg"},
                      {"tp": "kwbt", "k": "Office", "v": "pos"},
                      {"tp": "minrat", "u": 0, "m": 5},
                      {"tp": "fqb", "v": "on"}],
            "waitcodedays": {"B": 90, "Z": 180, "O": 365}};
        const dfltacct = {
            "dsType": "DigAcc", "dsId": "101", "firstname": "Digger",
            "created": "2019-10-11T00:00:00Z",
            "modified": "2019-10-11T00:00:00Z;1",
            "email": "support@diggerhub.com", "token": "none",
            "hubdat": "",
            "kwdefs": kwdefs,
            "igfolds": ["Ableton","Audiffex","Audio Music Apps"],
            "settings": settings,
            "musfs": ""};
        const demoacct = {
            "dsType": "DigAcc", "dsId": "1234",
            "created": "2021-01-26T17:21:11Z",
            "modified": "2023-02-13T22:58:45Z;13139", "batchconv": "",
            "email": "demo@diggerhub.com", "token": "faketokentoshowsignedin",
            "hubdat": "{\"privaccept\": \"2022-06-11T14:11:14.284Z\"}",
            "status": "Active", "firstname": "Demo", "digname": "Demo",
            "kwdefs": kwdefs,
            "igfolds": ["Ableton","Audiffex","Audio Music Apps"],
            "settings": settings,
            "musfs": [
                {"dsId": "1235", "digname": "afriend", "firstname": "A Friend",
                 "added": "2022-06-10T21:30:21Z",
                 "lastpull": "2023-02-13T00:38:48Z",
                 "lastheard": "2022-11-06T18:42:48Z",
                 "common": 7086, "dfltrcv": 57, "dfltsnd": 5294},
                {"dsId": "1236", "digname": "bfriend", "firstname": "B Friend",
                 "added": "2022-07-10T21:30:21Z",
                 "lastpull": "2023-02-20T00:38:48Z",
                 "lastheard": "2023-02-15T18:42:48Z",
                 "common": 556, "dfltrcv": 87, "dfltsnd": 5},
                {"dsId": "1237", "digname": "cfriend", "firstname": "C Friend",
                 "added": "2022-07-10T21:30:21Z",
                 "lastpull": "2023-02-20T00:38:48Z",
                 "lastheard": "2023-01-03T18:42:48Z",
                 "common": 556, "dfltrcv": 87, "dfltsnd": 42},
                {"dsId": "1238", "digname": "fabDJ", "firstname": "Fab DJ",
                 "added": "2022-08-10T21:30:21Z",
                 "lastpull": "2022-08-10T21:30:48Z",
                 "lastheard": "2023-02-14T18:42:48Z",
                 "common": 8645, "dfltrcv": 986, "dfltsnd": 0}]};
        const rets = {
            readConfig:{"acctsinfo": {currid:"1234",
                                      accts:[dfltacct, demoacct]}},
            readDigDat:{"version": "v1.1.3",
                        "scanned": "2023-02-13T20:42:12.320Z",
                        "songcount": 10,
                        "songs": {
                            "SongY.mp3": {"fq": "N","al": 40,"el": 70,"kws": "Office,Social","rv": 8,"path": "SongY.mp3","mrd": "C|Song Y|Artist Y|Album Y","ar": "Artist Y","ab": "Album Y","ti": "Song Y","lp":"2023-02-13T20:42:12.074Z"},
                            "SongX.mp3": {"fq": "N","al": 40,"el": 70,"kws": "Office,Social","rv": 8,"path": "SongX.mp3","mrd": "C|Song X|Artist X|Album X","ar": "Artist X","ab": "Album X","ti": "Song X","lp":"2023-02-13T20:42:12.074Z"},
                            "SongW.mp3": {"fq": "P","al": 40,"el": 70,"kws": "Office,Social","rv": 8,"path": "SongW.mp3","mrd": "C|Song W|Artist W|Album W","ar": "Artist W","ab": "Album W","ti": "Song W","lp":"2023-02-13T20:42:12.074Z"},
                            "SongV.mp3": {"fq": "N","al": 40,"el": 70,"kws": "Office,Social","rv": 8,"path": "SongV.mp3","mrd": "C|Song V|Artist V|Album V","ar": "Artist V","ab": "Album V","ti": "Song V","lp":"2023-02-13T20:42:12.074Z"},
                            "SongU.mp3": {"fq": "P","al": 40,"el": 70,"kws": "Office,Social","rv": 8,"path": "SongU.mp3","mrd": "C|Song U|Artist U|Album U","ar": "Artist U","ab": "Album U","ti": "Song U","lp":""},
                            "SongT.mp3": {"fq": "N","al": 40,"el": 70,"kws": "Office,Social","rv": 8,"path": "SongT.mp3","mrd": "C|Song T|Artist T|Album T","ar": "Artist T","ab": "Album T","ti": "Song T","lp":"2023-02-13T20:42:12.074Z"},
                            "SongS.mp3": {"fq": "N","al": 40,"el": 70,"kws": "Office,Social","rv": 8,"path": "SongS.mp3","mrd": "C|Song S|Artist S|Album S","ar": "Artist S","ab": "Album S","ti": "Song S","lp":"2023-02-13T20:42:12.074Z"},
                            "SongR.mp3": {"fq": "N","al": 40,"el": 70,"kws": "Office,Social","rv": 8,"path": "SongR.mp3","mrd": "C|Song R|Artist R|Album R","ar": "Artist R","ab": "Album R","ti": "Song R","lp":"2023-02-13T20:42:12.074Z"},
                            "SongQ.mp3": {"fq": "N","al": 40,"el": 70,"kws": "Office,Social","rv": 8,"path": "SongQ.mp3","mrd": "C|Song Q|Artist Q|Album Q","ar": "Artist Q","ab": "Album Q","ti": "Song Q","lp":"2023-02-13T20:42:12.074Z"},
                            "SongP.mp3": {"fq": "N","al": 40,"el": 70,"kws": "Office,Social","rv": 8,"path": "SongP.mp3","mrd": "C|Song P|Artist P|Album P","ar": "Artist P","ab": "Album P","ti": "Song P","lp":"2023-02-13T20:42:12.074Z"}},
                        "scanstart": "2023-02-13T20:42:12.274Z"},
            requestMediaRead:[{"path": "SongY.mp3","artist": "Artist Y","album": "Album Y","title": "Song Y", "lp":"2023-02-13T20:42:12.074Z"},
                              {"path": "SongX.mp3","artist": "Artist X","album": "Album X","title": "Song X", "lp":"2023-02-13T20:42:12.074Z"},
                              {"path": "SongW.mp3","artist": "Artist W","album": "Album W","title": "Song W", "lp":"2023-02-13T20:42:12.074Z"},
                              {"path": "SongV.mp3","artist": "Artist V","album": "Album V","title": "Song V", "lp":"2023-02-13T20:42:12.074Z"},
                              {"path": "SongU.mp3","artist": "Artist U","album": "Album U","title": "Song U", "lp":""},
                              {"path": "SongT.mp3","artist": "Artist T","album": "Album T","title": "Song T", "lp":"2023-02-13T20:42:12.074Z"},
                              {"path": "SongS.mp3","artist": "Artist S","album": "Album S","title": "Song S", "lp":"2023-02-13T20:42:12.074Z"},
                              {"path": "SongR.mp3","artist": "Artist R","album": "Album R","title": "Song R", "lp":"2023-02-13T20:42:12.074Z"},
                              {"path": "SongQ.mp3","artist": "Artist Q","album": "Album Q","title": "Song Q", "lp":"2023-02-13T20:42:12.074Z"},
                              {"path": "SongP.mp3","artist": "Artist P","album": "Album P","title": "Song P", "lp":"2023-02-13T20:42:12.074Z"}],
            "statusSync":dummyStatus,
            "pausePlayback":dummyStatus,
            "resumePlayback":dummyStatus,
            "seekToOffset":dummyStatus,
            "startPlayback":dummyStatus,
            "hubAcctCallacctok":[demoacct, "abcdef12345678"],
            "hubAcctCallmessages":[
                //bfriend thanks for sharing Song P
                {sndr:"1236", rcvr:"1234", msgtype:"shresp",
                 created:"2023-01-03T20:42:12.074Z", status:"open",
                 srcmsg:"fake", songid:"fake",
                 ti:"Song P", ar:"Artist P", ab:"Album P"},
                //afriend great Song G - Awesome bassline
                {sndr:"1235", rcvr:"1234", msgtype:"share",
                 created:"2023-01-04T20:42:12.074Z", status:"open",
                 srcmsg:"", songid:"fake",
                 ti:"Song G", ar:"Artist G", ab:"Album G",
                 nt:"Awesome bassline"},
                //fabDJ recommends Song J
                {sndr:"1238", rcvr:"1234", msgtype:"recommendation",
                 created:"2023-01-05T20:42:12.074Z", status:"open",
                 srcmsg:"", songid:"fake",
                 ti:"Song J", ar:"Artist J", ab:"Album J",
                 nt:"Super sticky original groove"},
                //cfriend thanks for recommending Song X
                {sndr:"1237", rcvr:"1234", msgtype:"recresp",
                 created:"2023-01-06T20:42:12.074Z", status:"open",
                 srcmsg:"fake", songid:"fake",
                 ti:"Song X", ar:"Artist X", ab:"Album X"},
                //afriend Song S - Melody gets stuck in my head every time.
                {sndr:"1235", rcvr:"1234", msgtype:"share",
                 created:"2023-01-07T20:42:12.074Z", status:"open",
                 srcmsg:"", songid:"fake",
                 ti:"Song S", ar:"Artist S", ab:"Album S",
                 nt:"Melody gets stuck in my head every time."}]};
    return {
        stubbed: function (iosFuncName, ignore /*param*/, callback/*, errf*/) {
            if(active && rets[iosFuncName]) {
                callback(rets[iosFuncName]);
                return true; }
            return false; }
    };  //end mgrs.scr returned functions
    }());


    //Media Playback manager handles transport and playback calls
    mgrs.mp = (function () {
        function deckPaths () {
            var qm = app.deck.stableDeckLength(); var paths;
            qm = app.player.dispatch("slp", "limitToSleepQueueMax", qm);
            const dst = app.deck.getState(qm);  //songs currently on deck
            if(dst.disp === "album") {
                paths = dst.disp.info.songs.map((s) => s.path); }
            else {  //send currently playing song as first path in list
                paths = dst.det.map((s) => s.path);
                paths.unshift(app.player.song().path); }
            return JSON.stringify(paths); }
        function notePlaybackState (stat) {
            app.player.dispatch("mob", "notePlaybackStatus", stat); }
    return {
        requestStatusUpdate: function (/*contf*/) {
            mgrs.ios.call("statusSync", deckPaths(), notePlaybackState); },
        pause: function () {
            mgrs.ios.call("pausePlayback", "", notePlaybackState); },
        resume: function () {
            mgrs.ios.call("resumePlayback", "", notePlaybackState); },
        seek: function (ms) {
            mgrs.ios.call("seekToOffset", String(ms), notePlaybackState); },
        playSong: function (/*path*/) {  //need entire queue, not just song
            mgrs.ios.call("startPlayback", deckPaths(), notePlaybackState); }
    };  //end mgrs.mp returned functions
    }());


    //Copy export manager handles playlist creation.  No file copying.
    mgrs.cpx = (function () {
    return {
        exportSongs: function (/*dat, statusfunc, contfunc, errfunc*/) {
            jt.log("svc.cpx.exportSongs not supported."); }
    };  //end mgrs.cpx returned functions
    }());


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
            const dbo = mgrs.loc.getDigDat();
            Object.values(dbo.songs).forEach(function (s) {  //mark all deleted
                s.fq = s.fq || "N";
                if(!s.fq.startsWith("D")) {
                    s.fq = "D" + s.fq; } });
            dbo.songcount = dais.length;
            jt.out("countspan", String(dbo.songcount) + "&nbsp;songs");
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
                mergeAudioData(dais);
                mgrs.loc.writeDigDat(function () {
                    jt.out(dbstatdiv, "");
                    app.top.markIgnoreSongs();
                    app.top.rebuildKeywords();
                    app.deck.update("rebuildSongData");
                    if(apresloadcmd === "rebuild") {
                        app.player.next(); } }); }); }
    };  //end mgrs.sg returned functions
    }());


    //Local manager handles local environment interaction
    mgrs.loc = (function () {
        var config = null;
        var dbo = null;
    return {
        getConfig: function () { return config; },
        getDigDat: function () { return dbo; },
        songs: function () { return mgrs.loc.getDigDat().songs; },
        writeConfig: function (cfg, contf/*, errf*/) {
            config = cfg;
            const pjson = JSON.stringify(cfg, null, 2);  //readable file
            mgrs.ios.call("writeConfig", pjson, contf); },
        getDatabase: function () { return dbo; },
        loadInitialData: function () {
            mgrs.ios.call("readConfig", null, function (cobj) {
                config = cobj || {};
                mgrs.ios.call("readDigDat", null, function (dobj) {
                    dbo = dobj || {};
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
        loadLibrary: function (procdivid) {
            mgrs.sg.loadLibrary(procdivid); },
        loadDigDat: function (cbf) {
            mgrs.ios.call("readDigDat", null, function (dobj) {
                dbo = dobj || {};
                dbo = mgrs.sg.verifyDatabase(dbo);
                cbf(dbo); }); },
        writeDigDat: function (cbf) {
            var stat = app.top.dispatch("dbc", "verifyDatabase", dbo);
            if(!stat.verified) {
                return jt.err("writeDigDat got bad data not writing: " +
                              JSON.stringify(stat)); }
            const datstr = JSON.stringify(dbo, null, 2);
            mgrs.ios.call("writeDigDat", datstr, cbf); },
        updateSong: function (song, contf/*, errf*/) {
            app.copyUpdatedSongData(song, dbo.songs[song.path]);
            mgrs.loc.writeDigDat(function () {
                jt.out("modindspan", "");  //turn off indicator light
                app.top.dispatch("srs", "syncToHub");  //sched sync
                if(contf) {
                    contf(dbo.songs[song.path]); } }); },
        noteUpdatedState: function (/*label*/) {
            //If label === "deck" and the IOS platform needs to keep info
            //outside the app UI, this is the place to update that data
            return; },
        fetchSongs: function (contf/*, errf*/) {  //call stack as if web call
            setTimeout(function () { contf(dbo.songs); }, 50); },
        fetchAlbum: function (contf/*, errf*/) {
            const ps = app.player.song();  //deck already checked not null
            mgrs.ios.call("fetchAlbum", JSON.stringify(ps), function (paths) {
                const songs = app.svc.songs();
                contf(paths.map((path) => songs[path])); }); },
        writeSongs: function () {
            mgrs.loc.writeDigDat(function () {
                jt.log("svc.loc.writeSongs completed successfully"); }); },
        procSyncData: function (res) {
            app.player.logCurrentlyPlaying("svc.loc.procSyncData");
            const updacc = res[0];
            updacc.diggerVersion = mgrs.gen.plat("appversion");
            app.deck.dispatch("hsu", "noteSynchronizedAccount", updacc);
            app.deck.dispatch("hsu", "updateSynchronizedSongs", res.slice(1));
            return res; },
        hubSyncDat: function (data, contf, errf) {
            const param = {endpoint:"/hubsync", method:"POST", "data":data};
            mgrs.ios.call("hubSyncDat", JSON.stringify(param), function (res) {
                res = mgrs.loc.procSyncData(res);
                contf(res); }, errf); },
        noteUpdatedSongData: function (updsong) {
            //on IOS the local database has already been updated, and
            //local memory is up to date.
            return dbo.songs[updsong.path]; },
        makeHubAcctCall: function (verb, endpoint, data, contf, errf) {
            const param = {"endpoint":"/" + endpoint, method:verb, "data":data};
            const fname = "hubAcctCall" + endpoint;
            if(mgrs.scr.stubbed(fname, param, contf, errf)) {
                jt.log(fname + " call handled by screenshot manager");
                return; }
            mgrs.ios.call(fname, JSON.stringify(param), contf, errf); }
    };  //end mgrs.loc returned functions
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
            var logmsg;
            var param = mqo.pobj || "";
            if(param && typeof param === "object") {  //object or array
                param = JSON.stringify(param); }
            const msg = (queueName + ":" + mqo.msgnum + ":" + mqo.fname + ":" +
                         param);
            logmsg = msg;
            if(logmsg.length > 250) {
                logmsg = msg.slice(0, 150) + "..." + msg.slice(-50); }
            jt.log("callIOS: " + logmsg);
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
        function logMessageText (mstr) {
            var logmsg = mstr;
            if(logmsg.length > 250) {
                logmsg = mstr.slice(0, 150) + "..." + mstr.slice(-50); }
            jt.log("ios.retv: " + logmsg); }
        function parseMessageText(mstr) {
            var res = "";
            logMessageText(mstr);
            const [qname, msgid, fname, ...msgtxt] = mstr.split(":");
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
            return {"qname":qname, "msgid":msgid, "fname":fname, "res":res}; }
        function parseErrorText (rmo) {
            var errmsg = rmo.res;
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
        function verifyQueueMatch(rmo) {
            if(!qs[rmo.qname].q.length) {
                jt.log("ios.retv no pending mssages in queue " + rmo.qname +
                       ". Ignoring.");
                return false; }
            if(qs[rmo.qname].q[0].fname !== rmo.fname) {
                jt.log("ios.retv queue " + rmo.qname + " expected fname " +
                       qs[rmo.qname].q[0].fname + " but received " +
                       rmo.fname + ". Ignoring.");
                return false; }
            const expmid = qs[rmo.qname].q[0].msgnum;
            const rcvmid = parseInt(rmo.msgid, 10);
            if(expmid !== rcvmid) {
                jt.log("ios.retv queue " + rmo.qname + " fname " + rmo.fname +
                       " expected msgid " + expmid + " but received " +
                       rcvmid + ". Continuing despite sequence error.");
                return true; }
            return true; }
    return {
        call: function (iosFuncName, paramObj, callback, errorf) {
            var cruft = null;
            if(mgrs.scr.stubbed(iosFuncName, paramObj, callback, errorf)) {
                jt.log(iosFuncName + " call handled by screenshot manager");
                return; }
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
            if(!verifyQueueMatch(rmo)) {
                return; }
            if(typeof rmo.res === "string" && rmo.res.startsWith("Error - ")) {
                parseErrorText(rmo); }
            const mqo = qs[rmo.qname].q.shift();
            try {
                if(rmo.errmsg) {
                    mqo.errf(rmo.errcode, rmo.errmsg); }
                else {
                    mqo.cbf(rmo.res); }
            } catch(e) {
                jt.log("ios.retv " + (rmo.errmsg? "error" : "success") +
                       " callback failed: " + e);
            }
            if(qs[rmo.qname].q.length) {  //process next in queue
                callIOS(rmo.qname, qs[rmo.qname].q[0]); } }
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
        updateMultipleSongs: function (/*updss, contf, errf*/) {
            jt.err("svc.gen.updateMultipleSongs is web only"); },
        initialize: function () {  //don't block init of rest of modules
            setTimeout(mgrs.loc.loadInitialData, 50);
            mgrs.ios.call("getVersionCode", null, function (val) {
                platconf.versioncode = val; });
            mgrs.ios.call("getAppVersion", null, function (val) {
                platconf.appversion = val; }); },
        docContent: function (docurl, contf) {
            var fn = jt.dec(docurl);
            var sidx = fn.lastIndexOf("/");
            if(sidx >= 0) {
                fn = fn.slice(sidx + 1); }
            mgrs.ios.call("docContent", "docs/" + fn, contf); },
        makeHubAcctCall: function (verb, endpoint, data, contf, errf) {
            mgrs.loc.makeHubAcctCall(verb, endpoint, data, contf, errf); },
        writeConfig: function (cfg, contf, errf) {
            mgrs.loc.writeConfig(cfg, contf, errf); },
        fanGroupAction: function (data, contf/*, errf*/) {
            const param = {endpoint:"/fangrpact", method:"POST", "data":data};
            //caller writes updated account data
            mgrs.ios.call("hubfangrpact", JSON.stringify(param), contf); },
        fanCollab: function (data, contf/*, errf*/) {
            const param = {endpoint:"/fancollab", method:"POST", "data":data};
            mgrs.ios.call("hubfanclab", JSON.stringify(param), function (res) {
                res = mgrs.loc.procSyncData(res);
                contf(res); }); },
        fanMessage: function (data, contf/*, errf*/) {
            if(mgrs.scr.stubbed("hubAcctCallmessages", data, contf)) {
                jt.log(iosFuncName + " call handled by screenshot manager");
                return; }
            const param = {endpoint:"/fanmsg", method:"POST", "data":data};
            mgrs.ios.call("hubfanmsg", JSON.stringify(param), contf); },
        copyToClipboard: function (txt, contf/*, errf*/) {
            mgrs.ios.call("copyToClipboard", txt, contf); }
    };  //end mgrs.gen returned functions
    }());

return {
    init: function () { mgrs.gen.initialize(); },
    plat: function (key) { return mgrs.gen.plat(key); },
    iosReturn: function (jsonstr) { mgrs.ios.retv(jsonstr); },
    loadDigDat: function (cbf) { mgrs.loc.loadDigDat(cbf); },
    songs: function () { return mgrs.loc.getDigDat().songs; },
    fetchSongs: function (cf, ef) { mgrs.loc.fetchSongs(cf, ef); },
    fetchAlbum: function (cf, ef) { mgrs.loc.fetchAlbum(cf, ef); },
    updateSong: function (song, cf, ef) { mgrs.loc.updateSong(song, cf, ef); },
    noteUpdatedState: function (label) { mgrs.loc.noteUpdatedState(label); },
    urlOpenSupp: function () { return false; }, //links break webview
    docContent: function (du, cf) { mgrs.gen.docContent(du, cf); },
    writeConfig: function (cfg, cf, ef) { mgrs.gen.writeConfig(cfg, cf, ef); },
    dispatch: function (mgrname, fname, ...args) {
        try {
            return mgrs[mgrname][fname].apply(app.svc, args);
        } catch(e) {
            console.log("top.dispatch: " + mgrname + "." + fname + " " + e +
                        " " + new Error("stack trace").stack);
        } }
};  //end of returned functions
}());
