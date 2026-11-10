#!/usr/bin/env node
// fetch-config-flutter.js — CLI kéo config bundle từ server Funtap về project Flutter.
//
// PORT từ fetch-config-2x.js (bản Cocos 2.4): Node thuần (chỉ https/http/fs/path — KHÔNG cần
// npm install). Khác chỗ ĐÍCH GHI, vì layout Flutter khác Cocos:
//   mainConfig     → android/app/src/main/assets/fg_main_config.json   (native đọc từ assets APK)
//                  + ios/Runner/fg_main_config.json                     (native đọc từ bundle)
//   google-services→ android/app/google-services.json
//   GoogleService  → ios/Runner/GoogleService-Info.plist
//   keystore       → android/<file> + android/key.properties (convention Flutter)
//   admob app id   → chèn manifestPlaceholder FGSDK_ADMOB_APP_ID vào android/app/build.gradle[.kts]
//
// Phần iOS làm thêm 2 việc mà Android không cần (bên Android AAR/assets tự lo):
//   Info.plist            → Facebook / AppsFlyer / ATT / GADApplicationIdentifier / URL scheme
//                           / SKAdNetwork — map field PORT verbatim từ extension Cocos 3.x
//   Runner.xcodeproj      → đăng ký fg_main_config.json + GoogleService-Info.plist vào
//                           "Copy Bundle Resources" (không có thì mainBundle không thấy file)
//
// Endpoint DÙNG CHUNG với Unity / Cocos: GET <baseUrl>/api/sdk/bundle, header X-API-Key.
//
// Dùng:  node fetch-config-flutter.js --key <APIKEY> [--url https://fgtool.funtapglobal.com]
//                                     [--project <root>] [--force]

'use strict';
var https = require('https');
var http = require('http');
var fs = require('fs');
var path = require('path');

var BUNDLE_PATH = '/api/sdk/bundle';
var DEFAULT_URL = 'https://fgtool.funtapglobal.com';
var COOLDOWN_SECONDS = 180; // chặn spam server (fgtool limit 30/10 phút)

function parseArgs(argv) {
    var o = {};
    for (var i = 2; i < argv.length; i++) {
        var a = argv[i];
        if (a === '--key') o.key = argv[++i];
        else if (a === '--url') o.url = argv[++i];
        else if (a === '--project') o.project = argv[++i];
        else if (a === '--force') o.force = true;
    }
    return o;
}

function ensureDir(dir) { fs.mkdirSync(dir, { recursive: true }); }

function writeTextIfChanged(filePath, content) {
    ensureDir(path.dirname(filePath));
    if (fs.existsSync(filePath) && fs.readFileSync(filePath, 'utf-8') === content) return false;
    fs.writeFileSync(filePath, content, 'utf-8');
    return true;
}
function writeBytesIfChanged(filePath, data) {
    ensureDir(path.dirname(filePath));
    if (fs.existsSync(filePath)) {
        var existing = fs.readFileSync(filePath);
        if (existing.length === data.length && existing.equals(data)) return false;
    }
    fs.writeFileSync(filePath, data);
    return true;
}
function extractMessage(json) {
    if (!json) return '';
    var key = '"message":"';
    var start = json.indexOf(key);
    if (start < 0) return json.slice(0, 200);
    var s = start + key.length;
    var end = json.indexOf('"', s);
    return end < 0 ? json.slice(s) : json.slice(s, end);
}

// ── HTTP GET bundle ───────────────────────────────────────────────────────────
function fetchBundle(apiKey, baseUrl) {
    return new Promise(function (resolve) {
        var u;
        try { u = new URL(baseUrl.replace(/\/+$/, '') + BUNDLE_PATH); }
        catch (e) { resolve({ ok: false, status: 0, error: 'URL khong hop le: ' + baseUrl }); return; }
        var isHttps = u.protocol === 'https:';
        var lib = isHttps ? https : http;
        var req = lib.request({
            protocol: u.protocol, hostname: u.hostname, port: u.port || (isHttps ? 443 : 80),
            path: u.pathname + u.search, method: 'GET',
            headers: { 'X-API-Key': apiKey, Accept: 'application/json' }
        }, function (res) {
            var chunks = [];
            res.on('data', function (c) { chunks.push(c); });
            res.on('end', function () {
                var body = Buffer.concat(chunks).toString('utf-8');
                var status = res.statusCode || 0;
                if (status < 200 || status >= 300) {
                    var msg = extractMessage(body);
                    var error;
                    if (status === 401) error = '401 Unauthorized — ' + msg + '. Lay key moi o tab SDK API.';
                    else if (status === 429) error = '429 Rate limit — Doi vai phut roi thu lai.';
                    else error = 'HTTP ' + status + ': ' + (msg || body.slice(0, 200));
                    resolve({ ok: false, status: status, error: error });
                    return;
                }
                try { resolve({ ok: true, status: status, bundle: JSON.parse(body) }); }
                catch (e) { resolve({ ok: false, status: status, error: 'Parse JSON loi: ' + e.message }); }
            });
        });
        req.on('error', function (e) { resolve({ ok: false, status: 0, error: 'Network error: ' + e.message }); });
        req.setTimeout(20000, function () { req.destroy(); resolve({ ok: false, status: 0, error: 'Timeout (20s).' }); });
        req.end();
    });
}

// ── Ghi AdMob app id ─────────────────────────────────────────────────────────
// ⚠️ PHẢI ghi vào android/gradle.properties, KHÔNG phải app/build.gradle:
// meta-data ${FGSDK_ADMOB_APP_ID} nằm trong manifest của PLUGIN, mà AGP thay
// placeholder bằng giá trị của module sở hữu manifest -> đặt ở app là vô tác dụng,
// APK sẽ mang app id TEST và quảng cáo không ra tiền. Plugin đọc property này.
function writeAdmobAppId(projectRoot, appId, log) {
    var KEY = 'FGSDK_ADMOB_APP_ID';
    if (!appId) {
        log.push('!! config KHONG co android.main_ads_config.google_admob_app_id'
            + ' -> giu app id TEST cua Google. Quang cao se KHONG ra tien o ban release.');
        return;
    }
    var file = path.join(projectRoot, 'android', 'gradle.properties');
    var src = fs.existsSync(file) ? fs.readFileSync(file, 'utf-8') : '';
    var re = new RegExp('^[ \t]*' + KEY + '[ \t]*=.*$', 'm');
    var line = KEY + '=' + appId;
    if (re.test(src)) {
        var next = src.replace(re, line);
        if (next === src) { log.push('-- AdMob app id (unchanged)'); return; }
        fs.writeFileSync(file, next, 'utf-8');
        log.push('OK AdMob app id (cap nhat) -> android/gradle.properties');
        return;
    }
    var pad = (src && src.charAt(src.length - 1) !== '\n') ? '\n' : '';
    fs.writeFileSync(file, src + pad + '\n# AdMob app id that (plugin FGSDK doc property nay)\n'
        + line + '\n', 'utf-8');
    log.push('OK AdMob app id -> android/gradle.properties');
}

// ── Chặn secret lọt vào git ─────────────────────────────
// Fetch kéo về keystore + key.properties + API key đã lưu. Dev lỡ commit là lộ khoá ký app.
// Tự thêm vào .gitignore (idempotent) cho chắc.
function protectGitignore(projectRoot, log) {
    var file = path.join(projectRoot, '.gitignore');
    var MARK = '# --- FGSDK: KHONG commit secret ---';
    var src = fs.existsSync(file) ? fs.readFileSync(file, 'utf-8') : '';
    if (src.indexOf(MARK) !== -1) { log.push('-- .gitignore da chan secret'); return; }
    var entries = [
        MARK,
        'android/key.properties',
        '*.keystore',
        '*.jks',
        '.fgsdk/',
        'android/app/google-services.json',
        'ios/Runner/GoogleService-Info.plist'
    ];
    var pad = (src && src.charAt(src.length - 1) !== '\n') ? '\n' : '';
    fs.writeFileSync(file, src + pad + '\n' + entries.join('\n') + '\n', 'utf-8');
    log.push('OK .gitignore += chan keystore/key.properties/API key/google-services');
}

// ═══ iOS: Info.plist ══════════════════════════════════════════════════════════
// Mirror `writeAdmobAppId` bên Android: giá trị lấy TỪ CONFIG nên phải làm ở bước fetch.
// Map field PORT verbatim từ bản Cocos 3.x (`source/ios/iosutils.ts::patchInfoPlist`)
// để 3 engine ra cùng một Info.plist — khác nhau chỉ là chỗ đọc file.
//
// Node thuần (bat copy file này ra root project, KHÔNG npm install) → tự parse/serialize
// XML plist thay vì dùng lib `plist`. Chỉ đụng key của SDK, key khác giữ nguyên.

function plistDecode(s) {
    return String(s).replace(/&lt;/g, '<').replace(/&gt;/g, '>')
        .replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&amp;/g, '&');
}
function plistEncode(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

// <dict> → object thường (giữ thứ tự key), <array> → Array, <string> → string,
// <true/><false/> → boolean; integer/real/data/date bọc {__t,v} để ghi lại y nguyên.
function plistParse(xml) {
    var i = 0;
    function skipJunk() {
        for (;;) {
            while (i < xml.length && /\s/.test(xml.charAt(i))) i++;
            if (xml.substr(i, 2) === '<?') { i = xml.indexOf('?>', i) + 2; continue; }
            if (xml.substr(i, 4) === '<!--') { i = xml.indexOf('-->', i) + 3; continue; }
            if (xml.substr(i, 2) === '<!') { i = xml.indexOf('>', i) + 1; continue; }
            break;
        }
    }
    function tag() {
        skipJunk();
        if (xml.charAt(i) !== '<') throw new Error('plist: mong doi tag tai ' + i);
        var end = xml.indexOf('>', i);
        if (end < 0) throw new Error('plist: tag khong dong');
        var raw = xml.slice(i + 1, end);
        i = end + 1;
        var self = raw.charAt(raw.length - 1) === '/';
        if (self) raw = raw.slice(0, -1);
        var close = raw.charAt(0) === '/';
        if (close) raw = raw.slice(1);
        return { name: raw.split(/\s/)[0], self: self, close: close };
    }
    function textUntil(name) {
        var at = xml.indexOf('</' + name, i);
        if (at < 0) throw new Error('plist: thieu </' + name + '>');
        var t = xml.slice(i, at);
        i = xml.indexOf('>', at) + 1;
        return t;
    }
    function value(t) {
        switch (t.name) {
            case 'dict': {
                var obj = {};
                if (t.self) return obj;
                for (;;) {
                    var k = tag();
                    if (k.close && k.name === 'dict') return obj;
                    if (k.name !== 'key') throw new Error('plist: trong <dict> phai la <key>');
                    var kn = plistDecode(k.self ? '' : textUntil('key'));
                    obj[kn] = value(tag());
                }
            }
            case 'array': {
                var arr = [];
                if (t.self) return arr;
                for (;;) {
                    var e = tag();
                    if (e.close && e.name === 'array') return arr;
                    arr.push(value(e));
                }
            }
            case 'string': return t.self ? '' : plistDecode(textUntil('string'));
            case 'true': case 'false':
                if (!t.self) textUntil(t.name);
                return t.name === 'true';
            default:
                return { __t: t.name, v: t.self ? '' : textUntil(t.name) };
        }
    }
    var root = tag();
    if (root.name !== 'plist') throw new Error('plist: khong thay <plist>');
    return value(tag());
}

function plistBuild(v) {
    function node(x, d) {
        var pad = new Array(d + 1).join('\t');
        if (x === true) return pad + '<true/>';
        if (x === false) return pad + '<false/>';
        if (typeof x === 'string') return pad + '<string>' + plistEncode(x) + '</string>';
        if (Array.isArray(x)) {
            if (!x.length) return pad + '<array/>';
            var items = x.map(function (e) { return node(e, d + 1); });
            return pad + '<array>\n' + items.join('\n') + '\n' + pad + '</array>';
        }
        if (x && typeof x === 'object' && x.__t) {
            return pad + '<' + x.__t + '>' + x.v + '</' + x.__t + '>';
        }
        var keys = Object.keys(x || {});
        if (!keys.length) return pad + '<dict/>';
        var body = keys.map(function (k) {
            return pad + '\t<key>' + plistEncode(k) + '</key>\n' + node(x[k], d + 1);
        });
        return pad + '<dict>\n' + body.join('\n') + '\n' + pad + '</dict>';
    }
    return [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">',
        '<plist version="1.0">',
        node(v, 0),
        '</plist>',
        ''
    ].join('\n');
}

function backupOnce(file) {
    var b = file + '.fgsdkbak';
    if (!fs.existsSync(b) && fs.existsSync(file)) fs.copyFileSync(file, b);
}

function patchInfoPlist(projectRoot, iosCfg, log) {
    var file = path.join(projectRoot, 'ios', 'Runner', 'Info.plist');
    if (!fs.existsSync(file)) { log.push('!! Khong thay ios/Runner/Info.plist -> bo qua patch iOS'); return; }
    if (!iosCfg) { log.push('!! config KHONG co muc "ios" -> bo qua Info.plist'); return; }

    var data;
    try { data = plistParse(fs.readFileSync(file, 'utf-8')); }
    catch (e) { log.push('!! Doc Info.plist loi (' + e.message + ') -> sua tay'); return; }

    var fb = iosCfg.facebook_configs || {};
    var af = iosCfg.appsflyer_configs || {};
    var ads = iosCfg.main_ads_config || {};
    var privacy = iosCfg.privacy_configs || {};
    var appKey = iosCfg.app_key || '';

    // Facebook (§9.5)
    if (fb.app_id) data.FacebookAppID = fb.app_id;
    if (fb.client_token) data.FacebookClientToken = fb.client_token;
    if (fb.app_name) data.FacebookDisplayName = fb.app_name;
    data.FacebookAutoLogAppEventsEnabled = true;
    data.FacebookAdvertiserIDCollectionEnabled = true;

    // URL scheme: fb<app_id> (Facebook) + gl<app_key> (deeplink SDK §12)
    if (!Array.isArray(data.CFBundleURLTypes)) data.CFBundleURLTypes = [];
    var hasScheme = function (scheme) {
        return data.CFBundleURLTypes.some(function (t) {
            return t && Array.isArray(t.CFBundleURLSchemes) && t.CFBundleURLSchemes.indexOf(scheme) !== -1;
        });
    };
    if (fb.app_id && !hasScheme('fb' + fb.app_id)) data.CFBundleURLTypes.push({ CFBundleURLSchemes: ['fb' + fb.app_id] });
    if (appKey && !hasScheme('gl' + appKey)) data.CFBundleURLTypes.push({ CFBundleURLSchemes: ['gl' + appKey] });

    // LSApplicationQueriesSchemes (Facebook)
    if (!Array.isArray(data.LSApplicationQueriesSchemes)) data.LSApplicationQueriesSchemes = [];
    ['fbapi', 'fb-messenger-share-api', 'fbauth2', 'fbshareextension'].forEach(function (s) {
        if (data.LSApplicationQueriesSchemes.indexOf(s) === -1) data.LSApplicationQueriesSchemes.push(s);
    });

    // AppsFlyer (§9.4)
    if (af.DevKey) data.AppsFlyerDevKey = af.DevKey;
    if (af.AppId) data.AppleAppID = af.AppId;

    // ATT (§6.1/§6.2) — mô tả xin quyền tracking
    if (privacy.users_tracking_usage_description) {
        data.NSUserTrackingUsageDescription = privacy.users_tracking_usage_description;
    }

    // AdMob app id (§8 backfill) — bên Android là manifestPlaceholder, iOS là key này.
    if (ads.google_admob_app_id) data.GADApplicationIdentifier = ads.google_admob_app_id;
    else log.push('!! config ios.main_ads_config KHONG co google_admob_app_id -> quang cao backfill se dung app id TEST');

    // Background modes + Firebase/notification: giữ đúng giá trị proven của bản Cocos.
    // ⚠️ FirebaseAppDelegateProxyEnabled=false: Firebase KHÔNG swizzle AppDelegate — plugin tự
    //    forward openURL (FGSDKFlutterPlugin addApplicationDelegate).
    if (!Array.isArray(data.UIBackgroundModes)) data.UIBackgroundModes = [];
    ['fetch', 'remote-notification'].forEach(function (m) {
        if (data.UIBackgroundModes.indexOf(m) === -1) data.UIBackgroundModes.push(m);
    });
    if (data.FirebaseCrashlyticsCollectionEnabled === undefined) data.FirebaseCrashlyticsCollectionEnabled = true;
    if (data.FirebaseAppDelegateProxyEnabled === undefined) data.FirebaseAppDelegateProxyEnabled = false;
    if (!data.UILocalNotificationSettings) data.UILocalNotificationSettings = ['alert', 'badge', 'sound'];
    if (!data.UIUserNotificationSettings) data.UIUserNotificationSettings = ['alert', 'badge', 'sound'];

    // SKAdNetworkItems — seed 2 ID như bản Cocos proven. VERIFY(mac): bổ sung theo network bật.
    if (!Array.isArray(data.SKAdNetworkItems)) data.SKAdNetworkItems = [];
    ['cstr6suwn9.skadnetwork', '4pfyvq9l8r.skadnetwork'].forEach(function (id) {
        var had = data.SKAdNetworkItems.some(function (it) { return it && it.SKAdNetworkIdentifier === id; });
        if (!had) data.SKAdNetworkItems.push({ SKAdNetworkIdentifier: id });
    });

    var out = plistBuild(data);
    if (fs.readFileSync(file, 'utf-8') === out) { log.push('-- Info.plist (unchanged)'); return; }
    backupOnce(file);
    fs.writeFileSync(file, out, 'utf-8');
    log.push('OK Info.plist <- Facebook/AppsFlyer/ATT/AdMob/URL scheme/SKAdNetwork');
}

// ═══ iOS: đăng ký resource vào Runner.xcodeproj ═══════════════════════════════
// Android chỉ cần copy file vào assets/ là APK mang theo; iOS thì file PHẢI nằm trong
// "Copy Bundle Resources" của target, không thì `[NSBundle mainBundle] pathForResource:`
// trả nil → FGSDKIOS bỏ init vì "thiếu fg_main_config.json". Trước đây README bảo dev tự
// kéo vào Xcode — giờ patch thẳng project.pbxproj (format OpenStep, đủ đều để sửa an toàn).
function pbxFileType(name) {
    if (/\.json$/i.test(name)) return 'text.json';
    if (/\.plist$/i.test(name)) return 'text.plist.xml';
    return 'text';
}
function pbxNewUuid(src) {
    for (;;) {
        var u = '';
        for (var i = 0; i < 24; i++) u += '0123456789ABCDEF'.charAt(Math.floor(Math.random() * 16));
        if (src.indexOf(u) === -1) return u;
    }
}
// Chèn 1 dòng vào cuối danh sách `files = ( … );` / `children = ( … );` của 1 block.
function pbxInsertInList(src, blockStart, listKey, line) {
    var at = src.indexOf(listKey + ' = (', blockStart);
    if (at < 0) return null;
    var close = src.indexOf(');', at);
    if (close < 0) return null;
    // `);` nam sau indent cua chinh no -> lui ve dau dong de chen truoc, khoi dinh indent.
    var lineStart = src.lastIndexOf('\n', close) + 1;
    return src.slice(0, lineStart) + line + src.slice(lineStart);
}

function registerIosResources(projectRoot, names, log) {
    var pbx = path.join(projectRoot, 'ios', 'Runner.xcodeproj', 'project.pbxproj');
    if (!fs.existsSync(pbx)) { log.push('!! Khong thay ios/Runner.xcodeproj/project.pbxproj -> add tay trong Xcode'); return; }
    var src = fs.readFileSync(pbx, 'utf-8');
    var orig = src;

    // (a) Resources build phase CUA TARGET Runner (project con co target RunnerTests, phase rong).
    var mTarget = /[0-9A-F]{24} \/\* Runner \*\/ = \{\s*isa = PBXNativeTarget;[\s\S]*?buildPhases = \(([\s\S]*?)\);/.exec(src);
    var phaseUuid = mTarget && (/([0-9A-F]{24}) \/\* Resources \*\//.exec(mTarget[1]) || [])[1];
    // (b) group Runner (co `path = Runner;`) — de file hien trong navigator, path tuong doi ios/Runner/.
    var groupStart = -1;
    var reGroup = /([0-9A-F]{24}) \/\* Runner \*\/ = \{\s*isa = PBXGroup;/g, mg;
    while ((mg = reGroup.exec(src)) !== null) {
        var blockEnd = src.indexOf('\n\t\t};', mg.index);
        if (blockEnd > 0 && src.slice(mg.index, blockEnd).indexOf('path = Runner;') !== -1) { groupStart = mg.index; break; }
    }
    if (!phaseUuid || groupStart < 0) {
        log.push('!! Khong doc duoc cau truc Runner.xcodeproj -> keo file vao target Runner bang tay trong Xcode');
        return;
    }

    names.forEach(function (name) {
        if (!fs.existsSync(path.join(projectRoot, 'ios', 'Runner', name))) return;
        if (src.indexOf('/* ' + name + ' in Resources */') !== -1) { log.push('-- ' + name + ' da trong Runner target (bo qua)'); return; }

        var fileRef = pbxNewUuid(src);
        var buildFile = pbxNewUuid(src + fileRef);

        var refLine = '\t\t' + fileRef + ' /* ' + name + ' */ = {isa = PBXFileReference; lastKnownFileType = '
            + pbxFileType(name) + '; path = ' + name + '; sourceTree = "<group>"; };\n';
        var bfLine = '\t\t' + buildFile + ' /* ' + name + ' in Resources */ = {isa = PBXBuildFile; fileRef = '
            + fileRef + ' /* ' + name + ' */; };\n';

        // Chen ngay truoc dong `/* End ... section */` (dong nay o cot 0, item thi thut 2 tab).
        var withRef = src.replace('/* End PBXFileReference section */', refLine + '/* End PBXFileReference section */');
        withRef = withRef.replace('/* End PBXBuildFile section */', bfLine + '/* End PBXBuildFile section */');
        // Chen 2 dong tren lam lech index -> dinh vi lai group Runner trong chuoi moi.
        var reG = /([0-9A-F]{24}) \/\* Runner \*\/ = \{\s*isa = PBXGroup;/g, m2;
        var gStart = -1;
        while ((m2 = reG.exec(withRef)) !== null) {
            var e2 = withRef.indexOf('\n\t\t};', m2.index);
            if (e2 > 0 && withRef.slice(m2.index, e2).indexOf('path = Runner;') !== -1) { gStart = m2.index; break; }
        }
        var next = pbxInsertInList(withRef, gStart, 'children', '\t\t\t\t' + fileRef + ' /* ' + name + ' */,\n');
        if (next) withRef = next;

        var pStart = withRef.indexOf(phaseUuid + ' /* Resources */ = {');
        next = pbxInsertInList(withRef, pStart, 'files', '\t\t\t\t' + buildFile + ' /* ' + name + ' in Resources */,\n');
        if (!next) { log.push('!! Khong chen duoc ' + name + ' vao Resources phase -> add tay'); return; }

        src = next;
        log.push('OK ' + name + ' -> Runner target (Copy Bundle Resources)');
    });

    if (src !== orig) { backupOnce(pbx); fs.writeFileSync(pbx, src, 'utf-8'); }
}

// ── Ghi bundle ra file ────────────────────────────────────────────────────────
function writeBundle(bundle, projectRoot) {
    var log = [];
    var androidAssets = path.join(projectRoot, 'android', 'app', 'src', 'main', 'assets');
    var androidApp = path.join(projectRoot, 'android', 'app');
    var androidDir = path.join(projectRoot, 'android');
    var iosRunner = path.join(projectRoot, 'ios', 'Runner');
    var files = bundle.files || {};

    if (bundle.gameCode || bundle.appName) {
        log.push('Game: ' + (bundle.gameCode || '?') + ' — ' + (bundle.appName || ''));
    }

    if (files.mainConfig && files.mainConfig.json != null) {
        var cfg = files.mainConfig.json;
        var json = JSON.stringify(cfg, null, 2);
        var a = writeTextIfChanged(path.join(androidAssets, 'fg_main_config.json'), json);
        log.push((a ? 'OK ' : '-- ') + 'fg_main_config.json -> android/app/src/main/assets/');
        var i = writeTextIfChanged(path.join(iosRunner, 'fg_main_config.json'), json);
        log.push((i ? 'OK ' : '-- ') + 'fg_main_config.json -> ios/Runner/');

        var appId = '';
        try { appId = cfg.android.main_ads_config.google_admob_app_id || ''; } catch (e) { /* ignore */ }
        writeAdmobAppId(projectRoot, appId, log);

        // iOS: tương đương writeAdmobAppId — key phụ thuộc config nên phải patch ở đây.
        patchInfoPlist(projectRoot, cfg.ios, log);
    }

    var android = files.googleServices && files.googleServices.android;
    if (android && android.contentBase64) {
        var w2 = writeBytesIfChanged(path.join(androidApp, android.filename),
            Buffer.from(android.contentBase64, 'base64'));
        log.push((w2 ? 'OK ' : '-- ') + android.filename + ' -> android/app/');
    }
    var ios = files.googleServices && files.googleServices.ios;
    if (ios && ios.contentBase64) {
        var w3 = writeBytesIfChanged(path.join(iosRunner, ios.filename),
            Buffer.from(ios.contentBase64, 'base64'));
        log.push((w3 ? 'OK ' : '-- ') + ios.filename + ' -> ios/Runner/');
    }

    // iOS bundle chi mang file da nam trong "Copy Bundle Resources" -> tu dang ky vao xcodeproj.
    registerIosResources(projectRoot, [
        'fg_main_config.json',
        (ios && ios.filename) || 'GoogleService-Info.plist',
        'iap_packs.json'
    ], log);

    var ks = files.keystore;
    if (ks && ks.contentBase64 && ks.filename) {
        var ksPath = path.join(androidDir, ks.filename);
        var w4 = writeBytesIfChanged(ksPath, Buffer.from(ks.contentBase64, 'base64'));
        log.push((w4 ? 'OK ' : '-- ') + ks.filename + ' -> android/');
        if (ks.info) {
            // key.properties: convention chuẩn của Flutter cho signing release.
            var props = [
                'storePassword=' + (ks.info.storePassword || ''),
                'keyPassword=' + (ks.info.keyPassword || ''),
                'keyAlias=' + (ks.info.alias || ''),
                'storeFile=' + ks.filename,
                ''
            ].join('\n');
            var pw = writeTextIfChanged(path.join(androidDir, 'key.properties'), props);
            log.push((pw ? 'OK ' : '-- ') + 'key.properties -> android/ (alias: ' + ks.info.alias + ')');
            log.push('   !! key.properties + keystore chua secret — DUNG commit vao git');
        }
    }

    protectGitignore(projectRoot, log);

    if (bundle.missing && bundle.missing.length) {
        log.push('!! Chua co tren server: ' + bundle.missing.join(', '));
    }
    return log;
}

// ── Lưu / đọc API key ─────────────────────────────────────────────────────────
function keyStore(projectRoot) { return path.join(projectRoot, '.fgsdk', 'fetch-flutter.json'); }
function loadState(projectRoot) {
    try { return JSON.parse(fs.readFileSync(keyStore(projectRoot), 'utf-8')) || {}; } catch (e) { return {}; }
}
function loadSavedKey(projectRoot) { return loadState(projectRoot).apiKey || ''; }
function saveKey(projectRoot, apiKey, url, lastFetch) {
    try {
        var p = keyStore(projectRoot); ensureDir(path.dirname(p));
        var st = loadState(projectRoot);
        st.apiKey = apiKey; st.url = url;
        if (lastFetch != null) st.lastFetch = lastFetch;
        fs.writeFileSync(p, JSON.stringify(st, null, 2), 'utf-8');
    } catch (e) { /* ignore */ }
}
function remainingCooldown(projectRoot) {
    var last = loadState(projectRoot).lastFetch;
    if (!last) return 0;
    var elapsed = Math.floor((Date.now() - last) / 1000);
    return Math.max(0, COOLDOWN_SECONDS - elapsed);
}

// ── main ──────────────────────────────────────────────────────────────────────
(function () {
    var args = parseArgs(process.argv);
    var projectRoot = args.project || process.cwd();
    // bat/cmd có thể truyền path dính dấu " thừa. Bỏ đi.
    projectRoot = projectRoot.replace(/^"+|"+$/g, '').replace(/[\\/]+"?$/, '');
    var baseUrl = args.url || DEFAULT_URL;
    var apiKey = args.key || loadSavedKey(projectRoot);

    if (!fs.existsSync(path.join(projectRoot, 'pubspec.yaml'))) {
        console.error('[fetch] LOI: khong thay pubspec.yaml — chay o ROOT project Flutter.');
        process.exit(2);
    }
    if (!apiKey) {
        console.error('[fetch] LOI: thieu API Key. Chay: node fetch-config-flutter.js --key <APIKEY>');
        process.exit(2);
    }
    var cd = remainingCooldown(projectRoot);
    if (cd > 0 && !args.force) {
        console.error('[fetch] Cooldown: doi ' + cd + 's nua roi thu lai (chan spam server, limit 30/10phut).');
        console.error('[fetch] Muon bo qua ngay: chay lai voi --force');
        process.exit(3);
    }
    console.log('[fetch] Server : ' + baseUrl + BUNDLE_PATH);
    console.log('[fetch] Project: ' + projectRoot);
    fetchBundle(apiKey, baseUrl).then(function (r) {
        if (!r.ok) { console.error('[fetch] THAT BAI: ' + r.error); process.exit(1); }
        var log = writeBundle(r.bundle, projectRoot);
        log.forEach(function (l) { console.log('   ' + l); });
        saveKey(projectRoot, apiKey, baseUrl, Date.now());
        console.log('[fetch] XONG.');
        process.exit(0);
    });
})();
