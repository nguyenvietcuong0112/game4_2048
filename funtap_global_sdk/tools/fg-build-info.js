#!/usr/bin/env node
/*
 * fg-build-info.js — sinh file BUILD INFO cạnh thư mục build, cho CẢ 3 engine
 * (Cocos 3.x · Cocos 2.x · Flutter) và CẢ 2 nền (Android · iOS).
 *
 * PORT từ Unity `Packages/com.funtap.global.sdk/Public/Editor/BuildInfo.cs`
 * (FGBuildInfoCollector). Giữ nguyên bố cục + tên section + căn cột để người soát build
 * đọc file của Unity và của Cocos/Flutter thấy y hệt nhau.
 *
 * KHÁC Unity ở NGUỒN dữ liệu (bắt buộc, vì không có PlayerSettings/EDM4U):
 *   - id quảng cáo / key / devkey        → fg_main_config.json (cả nhánh android + ios)
 *   - version third-party Android        → fgsdk-deps.gradle (bản pin trong package)
 *   - version third-party iOS            → ios Podfile.lock (bản CocoaPods thật sự giải ra);
 *                                          chưa `pod install` thì báo rõ thay vì đoán
 *   - package name / app version         → build.gradle[.kts] | Info.plist | pubspec.yaml
 *
 * Luôn in CẢ [Android] LẪN [iOS] dù build nền nào — config chứa cả hai, và lệch nhau
 * giữa 2 nền là thứ hay lọt nhất khi soát build.
 *
 * Dùng:
 *   node fg-build-info.js --project <root> --engine flutter|cocos3x|cocos2x
 *                         --platform android|ios [--out <file|dir>]
 *                         [--config <fg_main_config.json>] [--deps <fgsdk-deps.gradle>]
 *                         [--podlock <Podfile.lock>] [--sdk-version 3.2.6]
 *                         [--pkg-version 1.0.0] [--build-output <path>]
 */

'use strict';
var fs = require('fs');
var path = require('path');

var W = 63;                       // bề ngang kẻ ngang — khớp Unity ("─".PadRight(63))
var SDK_VERSION_DEFAULT = '3.2.6'; // verbatim Unity FunGlobalSDK

// ── tiện ích ─────────────────────────────────────────────────────────────────
function rule(ch) { return new Array(W + 1).join(ch || '─'); }
function pad(s, n) { s = String(s); return s + new Array(Math.max(1, n - s.length + 1)).join(' '); }
function row(label, value) { return pad(label, 18) + ': ' + (value === undefined || value === null || value === '' ? 'null' : value); }
function readJson(p) { try { return JSON.parse(fs.readFileSync(p, 'utf-8')); } catch (e) { return null; } }
function readText(p) { try { return fs.readFileSync(p, 'utf-8'); } catch (e) { return ''; } }
function exists(p) { try { return !!p && fs.existsSync(p); } catch (e) { return false; } }
function stamp(d) {
    function p2(n) { return (n < 10 ? '0' : '') + n; }
    return d.getFullYear() + '-' + p2(d.getMonth() + 1) + '-' + p2(d.getDate()) + ' ' +
        p2(d.getHours()) + ':' + p2(d.getMinutes()) + ':' + p2(d.getSeconds());
}
function firstExisting(list) {
    for (var i = 0; i < list.length; i++) if (exists(list[i])) return list[i];
    return '';
}

function parseArgs(argv) {
    var o = {}, map = {
        '--project': 'project', '--engine': 'engine', '--platform': 'platform', '--out': 'out',
        '--config': 'config', '--deps': 'deps', '--podlock': 'podlock',
        '--sdk-version': 'sdkVersion', '--pkg-version': 'pkgVersion', '--build-output': 'buildOutput'
    };
    for (var i = 2; i < argv.length; i++) {
        var k = map[argv[i]];
        if (k) o[k] = argv[++i];
    }
    return o;
}

// ── version third-party ──────────────────────────────────────────────────────
// Android: đọc thẳng fgsdk-deps.gradle (bản pin đi kèm package) — đây CHÍNH là version
// sẽ vào APK, vì AAR không gói kèm third-party.
function androidDeps(depsPath) {
    var src = readText(depsPath), out = {};
    if (!src) return out;
    // implementation("group:artifact:version")  |  platform("group:artifact:version")
    var re = /(?:implementation|api)\s*\(\s*(?:platform\s*\(\s*)?["']([^"':]+):([^"':]+):?([^"']*)["']/g, m;
    while ((m = re.exec(src)) !== null) {
        out[m[1] + ':' + m[2]] = m[3] || '(theo BOM)';
    }
    return out;
}
function dep(map, key) { return map[key] || ''; }

// iOS: Podfile.lock là nơi DUY NHẤT biết version thật (podspec của SDK cố tình không pin).
function iosPods(lockPath) {
    var src = readText(lockPath), out = {};
    if (!src) return out;
    var lines = src.split(/\r?\n/), inPods = false;
    for (var i = 0; i < lines.length; i++) {
        var l = lines[i];
        if (/^PODS:/.test(l)) { inPods = true; continue; }
        if (inPods && /^\S/.test(l)) break;               // hết khối PODS
        if (!inPods) continue;
        var m = /^\s{2}-\s+([^\s(]+)\s+\(([^)]+)\)/.exec(l); // "  - FirebaseAnalytics (11.6.0):"
        if (m) out[m[1]] = m[2];
    }
    return out;
}
function pod(map, name) {
    if (map[name]) return map[name];
    // pod con: "FirebaseAnalytics/AdIdSupport" → lấy bản gốc nếu có
    var keys = Object.keys(map);
    for (var i = 0; i < keys.length; i++) if (keys[i].indexOf(name + '/') === 0) return map[keys[i]];
    return '';
}

var MAX_ADAPTERS = [
    { name: 'BidMachine',       androidKey: 'bidmachine-adapter',        iosPod: 'AppLovinMediationBidMachineAdapter' },
    { name: 'BigoAds',          androidKey: 'bigoads-adapter',           iosPod: 'AppLovinMediationBigoAdsAdapter' },
    { name: 'ByteDance/Pangle', androidKey: 'bytedance-adapter',         iosPod: 'AppLovinMediationByteDanceAdapter' },
    { name: 'Facebook/Meta',    androidKey: 'facebook-adapter',          iosPod: 'AppLovinMediationFacebookAdapter' },
    { name: 'Fyber/DTExchange', androidKey: 'fyber-adapter',             iosPod: 'AppLovinMediationFyberAdapter' },
    { name: 'Google AdMob',     androidKey: 'google-adapter',            iosPod: 'AppLovinMediationGoogleAdapter' },
    { name: 'Google AdManager', androidKey: 'google-ad-manager-adapter', iosPod: 'AppLovinMediationGoogleAdManagerAdapter' },
    { name: 'InMobi',           androidKey: 'inmobi-adapter',            iosPod: 'AppLovinMediationInMobiAdapter' },
    { name: 'IronSource',       androidKey: 'ironsource-adapter',        iosPod: 'AppLovinMediationIronSourceAdapter' },
    { name: 'Mintegral',        androidKey: 'mintegral-adapter',         iosPod: 'AppLovinMediationMintegralAdapter' },
    { name: 'Moloco',           androidKey: 'moloco-adapter',            iosPod: 'AppLovinMediationMolocoAdapter' },
    { name: 'UnityAds',         androidKey: 'unityads-adapter',          iosPod: 'AppLovinMediationUnityAdsAdapter' },
    { name: 'Vungle/Liftoff',   androidKey: 'vungle-adapter',            iosPod: 'AppLovinMediationVungleAdapter' },
    { name: 'Yandex',           androidKey: 'yandex-adapter',            iosPod: 'AppLovinMediationYandexAdapter' }
];

function androidAdapters(projectRoot) {
    var out = {};
    var gradle = readText(firstExisting([
        path.join(projectRoot, 'android', 'app', 'build.gradle.kts'),
        path.join(projectRoot, 'android', 'app', 'build.gradle'),
        path.join(projectRoot, 'build', 'android', 'proj', 'app', 'build.gradle')
    ]));
    if (!gradle) return out;
    var re = /implementation\s*\(\s*["']com\.applovin\.mediation:([^"':]+):?([^"']*)["']\s*\)/g, m;
    while ((m = re.exec(gradle)) !== null) {
        out[m[1]] = m[2] || '+';
    }
    return out;
}

// ── thông tin app theo engine ────────────────────────────────────────────────
function appInfo(ctx) {
    var out = { packageName: '', appName: '', appVersion: '' };

    // Android: applicationId + versionName trong app/build.gradle[.kts]
    var gradle = readText(firstExisting([
        path.join(ctx.project, 'android', 'app', 'build.gradle.kts'),
        path.join(ctx.project, 'android', 'app', 'build.gradle'),
        path.join(ctx.project, 'build', 'android', 'proj', 'app', 'build.gradle')
    ]));
    if (gradle) {
        var m = /applicationId\s*=?\s*["']([^"']+)["']/.exec(gradle);
        if (m) out.packageName = m[1];
        var v = /versionName\s*=?\s*["']([^"']+)["']/.exec(gradle);
        if (v) out.appVersion = v[1];
    }

    // iOS: Info.plist (CFBundleShortVersionString / CFBundleDisplayName)
    var plist = readText(firstExisting([
        path.join(ctx.project, 'ios', 'Runner', 'Info.plist'),
        path.join(ctx.project, 'build', 'ios', 'proj', 'Info.plist')
    ]));
    if (plist) {
        var pv = /<key>CFBundleShortVersionString<\/key>\s*<string>([^<]*)<\/string>/.exec(plist);
        if (pv && !out.appVersion) out.appVersion = pv[1];
        var pn = /<key>CFBundleDisplayName<\/key>\s*<string>([^<]*)<\/string>/.exec(plist);
        if (pn) out.appName = pn[1];
    }

    // Flutter: pubspec.yaml là nguồn chuẩn của version (ghi đè cái đoán ở trên)
    var pubspec = readText(path.join(ctx.project, 'pubspec.yaml'));
    if (pubspec) {
        var pm = /^version:\s*(.+)$/m.exec(pubspec);
        if (pm) out.appVersion = pm[1].trim();
        var nm = /^name:\s*(.+)$/m.exec(pubspec);
        if (nm && !out.appName) out.appName = nm[1].trim();
    }
    return out;
}

// ── bảng ad unit ─────────────────────────────────────────────────────────────
var FORMATS = ['Interstitial', 'Rewarded', 'Banner', 'AppOpen', 'MRec'];

function maxUnits(info, label, plat) {
    info.push(label);
    var ads = plat && plat.main_ads_config;
    if (!ads || !ads.primaryAdUnitConfig) { info.push('  (không có main_ads_config)'); return; }
    FORMATS.forEach(function (f) {
        var u = ads.primaryAdUnitConfig[f] || {};
        var id = u.AdUnitID || 'null';
        var state = u.EnableAds ? 'ENABLED' : 'DISABLED';
        var auto = u.IsAutoLoad ? ', autoload' : '';
        info.push('  ' + pad(f, 17) + ': ' + id + ' [' + state + auto + ']');
    });
}

function admobUnits(info, label, plat) {
    info.push(label);
    var ads = plat && plat.main_ads_config;
    if (!ads || !ads.backfillConfig) { info.push('  (không có backfillConfig)'); return; }
    FORMATS.forEach(function (f) {
        var u = ads.backfillConfig[f] || {};
        var id = u.AdUnitID || 'null';
        var state = u.Enable ? 'ENABLED' : 'DISABLED';
        var auto = u.IsAutoLoad ? ', autoload' : '';
        info.push('  ' + pad(f, 17) + ': ' + id + ' [' + state + auto + ']');
    });
}

// Chỉ ra ngay chỗ 2 nền lệch nhau — lỗi hay lọt nhất khi soát build.
function diffAndroidIos(info, and, ios) {
    var diffs = [];
    function cmp(name, a, b) { if ((a || '') !== (b || '')) diffs.push(name); }
    var aa = (and && and.main_ads_config) || {}, ia = (ios && ios.main_ads_config) || {};
    cmp('max_sdk_key', aa.max_sdk_key, ia.max_sdk_key);
    cmp('MediationType', and && and.MediationType, ios && ios.MediationType);
    cmp('primaryProvider', aa.primaryProvider, ia.primaryProvider);
    cmp('app_key', and && and.app_key, ios && ios.app_key);
    cmp('game_code', and && and.game_code, ios && ios.game_code);
    cmp('facebook app_id', (and && and.facebook_configs || {}).app_id, (ios && ios.facebook_configs || {}).app_id);
    cmp('appsflyer DevKey', (and && and.appsflyer_configs || {}).DevKey, (ios && ios.appsflyer_configs || {}).DevKey);
    FORMATS.forEach(function (f) {
        var u1 = (aa.primaryAdUnitConfig || {})[f] || {}, u2 = (ia.primaryAdUnitConfig || {})[f] || {};
        if (!!u1.EnableAds !== !!u2.EnableAds) diffs.push('MAX ' + f + '.EnableAds');
        var b1 = (aa.backfillConfig || {})[f] || {}, b2 = (ia.backfillConfig || {})[f] || {};
        if (!!b1.Enable !== !!b2.Enable) diffs.push('AdMob ' + f + '.Enable');
    });
    info.push(rule());
    info.push('ANDROID vs iOS');
    if (!diffs.length) { info.push('  (khớp nhau ở mọi field đối chiếu)'); return; }
    info.push('  Lệch: ' + diffs.join(', '));
    info.push('  → Cố ý thì bỏ qua; không cố ý thì sửa fg_main_config.json rồi build lại.');
}

// ── render ───────────────────────────────────────────────────────────────────
function render(ctx) {
    var cfg = ctx.config || {};
    var and = cfg.android || null;
    var ios = cfg.ios || null;
    var cur = ctx.platform === 'ios' ? ios : and;
    var A = ctx.androidDeps || {};
    var P = ctx.iosPods || {};
    var info = [];

    info.push(rule('═'));
    info.push('BUILD INFO — ' + stamp(new Date()));
    info.push(rule('═'));
    info.push('');

    info.push('BASIC BUILD INFO');
    info.push(rule());
    info.push(row('Engine', ctx.engineLabel));
    info.push(row('Platform', ctx.platform === 'ios' ? 'iOS' : 'Android'));
    info.push(row('Build Type', ctx.platform === 'ios' ? 'Xcode project' : 'APK/AAB'));
    // Hai nguồn package name KHÁC nhau và lệch là lỗi thật: `package_name` trong config là cái
    // Funtap đăng ký (tracking/backend dựa vào), còn applicationId/bundle id là cái APK/IPA mang đi.
    var pkgBuild = ctx.app.packageName;
    var pkgConfig = cur && cur.package_name;
    info.push(row('Package Name', pkgBuild || '(không đọc được từ build file)'));
    info.push(row('Package (config)', pkgConfig + (pkgBuild && pkgConfig && pkgBuild !== pkgConfig
        ? '   ← LỆCH với package name của app' : '')));
    info.push(row('App Name', ctx.app.appName || (cur && cur.facebook_configs && cur.facebook_configs.app_name)));
    info.push(row('App Version', ctx.app.appVersion));
    info.push(row('Game Code', cur && cur.game_code));
    info.push(row('App Key', cur && cur.app_key));
    info.push(row('Build Date/Time', stamp(new Date())));
    if (ctx.buildOutput) info.push(row('Build Output', ctx.buildOutput));
    info.push(row('Config', ctx.configPath || '(KHÔNG tìm thấy fg_main_config.json)'));
    info.push('');

    info.push(rule());
    info.push('FUNTAP GLOBAL SDK');
    info.push(row('Version', ctx.sdkVersion));
    info.push(row('Package', ctx.pkgLabel));
    info.push(row('MediationType', cur && cur.MediationType));
    info.push(row('Primary Provider', cur && cur.main_ads_config && cur.main_ads_config.primaryProvider));
    info.push(row('Base API', cur && cur.base_api_domain));
    var devices = (cfg.listDevice || []).length;
    info.push(row('Test devices', devices + (devices ? '  ← listDevice trong config, XOÁ trước khi phát hành' : '')));
    info.push(row('IAP packs', ctx.iapSummary));
    info.push('');

    info.push(rule());
    info.push('GOOGLE MOBILE ADS');
    info.push(row('Version', 'Android ' + (dep(A, 'com.google.android.gms:play-services-ads') || 'unknown') +
        ', iOS ' + (pod(P, 'Google-Mobile-Ads-SDK') || 'chưa pod install')));
    info.push(row('Android App ID', and && and.main_ads_config && and.main_ads_config.google_admob_app_id));
    info.push(row('iOS App ID', ios && ios.main_ads_config && ios.main_ads_config.google_admob_app_id));
    info.push('Backfill ad units :');
    admobUnits(info, '[Android]', and);
    admobUnits(info, '[iOS]', ios);
    info.push('');

    info.push(rule());
    info.push('APPLOVIN MAX');
    info.push(row('SDK Version', 'Android ' + (dep(A, 'com.applovin:applovin-sdk') || 'unknown') +
        ', iOS ' + (pod(P, 'AppLovinSDK') || 'chưa pod install')));
    info.push(row('SDK Key [Android]', and && and.main_ads_config && and.main_ads_config.max_sdk_key));
    info.push(row('SDK Key [iOS]', ios && ios.main_ads_config && ios.main_ads_config.max_sdk_key));
    info.push('Ad units          :');
    maxUnits(info, '[Android]', and);
    maxUnits(info, '[iOS]', ios);
    info.push('');

    info.push(rule());
    info.push('APPLOVIN MAX MEDIATION ADAPTERS (14 networks)');
    var andAdapters = androidAdapters(ctx.project);
    MAX_ADAPTERS.forEach(function (ad) {
        var a = andAdapters[ad.androidKey];
        var p = pod(P, ad.iosPod);
        var andText = a ? ('Android (' + a + ')') : 'Android (chưa gắn)';
        var iosText = p ? ('iOS ' + p) : 'iOS (chưa gắn)';
        info.push('- ' + pad(ad.name, 19) + ': ' + andText + ' | ' + iosText);
    });
    info.push('');

    info.push(rule());
    info.push('FIREBASE MODULES');
    info.push('- ' + pad('Android BOM', 18) + ': ' + (dep(A, 'com.google.firebase:firebase-bom') || 'unknown'));
    ['firebase-analytics', 'firebase-messaging', 'firebase-config'].forEach(function (mod) {
        info.push('- ' + pad('Android ' + mod.replace('firebase-', ''), 18) + ': ' + (dep(A, 'com.google.firebase:' + mod) || 'unknown'));
    });
    info.push('- ' + pad('iOS Analytics', 18) + ': ' + (pod(P, 'FirebaseAnalytics') || 'chưa pod install'));
    info.push('- ' + pad('iOS RemoteConfig', 18) + ': ' + (pod(P, 'FirebaseRemoteConfig') || 'chưa pod install'));
    info.push(row('google-services', ctx.googleServices));
    info.push('');

    info.push(rule());
    info.push('APPSFLYER');
    info.push(row('Version', 'Android ' + (dep(A, 'com.appsflyer:af-android-sdk') || 'unknown') +
        ', iOS ' + (pod(P, 'AppsFlyerFramework') || 'chưa pod install')));
    info.push(row('DevKey [Android]', and && and.appsflyer_configs && and.appsflyer_configs.DevKey));
    info.push(row('DevKey [iOS]', ios && ios.appsflyer_configs && ios.appsflyer_configs.DevKey));
    info.push(row('Apple App ID', ios && ios.appsflyer_configs && ios.appsflyer_configs.AppId));
    info.push(row('ROI360 (Connector)', 'Android ' + (dep(A, 'com.appsflyer:purchase-connector') || 'unknown') +
        ', iOS ' + (pod(P, 'PurchaseConnector') || 'chưa pod install')));
    info.push('');

    info.push(rule());
    info.push('FACEBOOK SDK');
    info.push(row('Version', 'Android ' + (dep(A, 'com.facebook.android:facebook-android-sdk') || 'unknown') +
        ', iOS ' + (pod(P, 'FBSDKCoreKit') || 'chưa pod install')));
    info.push(row('App ID [Android]', and && and.facebook_configs && and.facebook_configs.app_id));
    info.push(row('App ID [iOS]', ios && ios.facebook_configs && ios.facebook_configs.app_id));
    info.push(row('Client Token', cur && cur.facebook_configs && cur.facebook_configs.client_token));
    info.push(row('App Name', cur && cur.facebook_configs && cur.facebook_configs.app_name));
    info.push('');

    info.push(rule());
    info.push('IAP / BILLING');
    info.push(row('Version', 'Android ' + (dep(A, 'com.android.billingclient:billing-ktx') || 'unknown') + ', iOS StoreKit 1'));
    info.push('');

    info.push(rule());
    info.push('CONSENT (UMP)');
    info.push(row('Version', 'Android ' + (dep(A, 'com.google.android.ump:user-messaging-platform') || 'unknown') +
        ', iOS ' + (pod(P, 'GoogleUserMessagingPlatform') || 'chưa pod install')));
    info.push('');

    diffAndroidIos(info, and, ios);
    info.push('');
    info.push(rule('═'));
    info.push('');
    return info.join('\n');
}

// ── thu thập + ghi file ──────────────────────────────────────────────────────
function iapSummary(p) {
    if (!exists(p)) return 'KHÔNG có iap_packs.json → IAP init false';
    var j = readJson(p);
    if (!j) return 'iap_packs.json PARSE LỖI';
    return (j.consumablePack || []).length + ' consumable / ' +
        (j.nonConsumablePack || []).length + ' non-consumable / ' +
        (j.subscriptionPack || []).length + ' subscription';
}

var ENGINE = {
    flutter: {
        label: 'Flutter',
        config: function (r, plat) {
            return plat === 'ios'
                ? path.join(r, 'ios', 'Runner', 'fg_main_config.json')
                : path.join(r, 'android', 'app', 'src', 'main', 'assets', 'fg_main_config.json');
        },
        iap: function (r, plat) {
            return plat === 'ios'
                ? path.join(r, 'ios', 'Runner', 'iap_packs.json')
                : path.join(r, 'android', 'app', 'src', 'main', 'assets', 'iap_packs.json');
        },
        deps: function (r) { return path.join(r, 'funtap_global_sdk', 'android', 'fgsdk-deps.gradle'); },
        podlock: function (r) { return path.join(r, 'ios', 'Podfile.lock'); },
        gsvc: function (r, plat) {
            return plat === 'ios' ? path.join(r, 'ios', 'Runner', 'GoogleService-Info.plist')
                : path.join(r, 'android', 'app', 'google-services.json');
        },
        out: function (r, plat) {
            return plat === 'ios' ? path.join(r, 'build', 'ios')
                : path.join(r, 'build', 'app', 'outputs', 'flutter-apk');
        }
    },
    cocos3x: {
        label: 'Cocos Creator 3.x',
        config: function (r) { return path.join(r, 'assets', 'resources', 'fg_main_config.json'); },
        iap: function (r) { return path.join(r, 'assets', 'resources', 'iap_packs.json'); },
        deps: function (r) { return path.join(r, 'extensions', 'fgsdk', 'plugins', 'android', 'fgsdk-deps.gradle'); },
        podlock: function (r) { return path.join(r, 'build', 'ios', 'proj', 'Podfile.lock'); },
        gsvc: function (r) { return path.join(r, 'assets', 'resources', 'google-services.json'); },
        out: function (r, plat) { return path.join(r, 'build', plat === 'ios' ? 'ios' : 'android'); }
    },
    cocos2x: {
        label: 'Cocos Creator 2.4.x',
        config: function (r) { return path.join(r, 'assets', 'resources', 'fg_main_config.json'); },
        iap: function (r) { return path.join(r, 'assets', 'resources', 'iap_packs.json'); },
        deps: function (r) { return path.join(r, 'fgsdk-native', 'android', 'fgsdk-deps.gradle'); },
        podlock: function (r) { return path.join(r, 'build', 'jsb-link', 'frameworks', 'runtime-src', 'proj.ios_mac', 'Podfile.lock'); },
        gsvc: function (r) { return path.join(r, 'assets', 'resources', 'google-services.json'); },
        out: function (r, plat) {
            return plat === 'ios'
                ? path.join(r, 'build', 'jsb-link', 'frameworks', 'runtime-src', 'proj.ios_mac')
                : path.join(r, 'build', 'jsb-link', 'frameworks', 'runtime-src', 'proj.android-studio');
        }
    }
};

function generate(opts) {
    var root = String(opts.project || process.cwd()).replace(/^"+|"+$/g, '').replace(/[\\/]+"?$/, '');
    var engine = ENGINE[opts.engine] || ENGINE.flutter;
    var platform = opts.platform === 'ios' ? 'ios' : 'android';

    var configPath = opts.config || engine.config(root, platform);
    var cfg = readJson(configPath);
    var ctx = {
        project: root,
        platform: platform,
        engineLabel: engine.label,
        pkgLabel: opts.pkgVersion || '(không rõ version package)',
        sdkVersion: opts.sdkVersion || SDK_VERSION_DEFAULT,
        config: cfg,
        configPath: cfg ? configPath : '',
        androidDeps: androidDeps(opts.deps || engine.deps(root)),
        iosPods: iosPods(opts.podlock || engine.podlock(root)),
        iapSummary: iapSummary(engine.iap(root, platform)),
        googleServices: exists(engine.gsvc(root, platform)) ? 'có' : 'KHÔNG có (Firebase sẽ không init)',
        buildOutput: opts.buildOutput || ''
    };
    ctx.app = appInfo(ctx);

    var text = render(ctx);

    // Đích ghi: --out là file thì dùng thẳng; là thư mục (hoặc bỏ trống) thì
    // <thư mục build>/<tên>_BUILD_INFO.txt — Unity cũng đặt cạnh sản phẩm build.
    var dest = opts.out || engine.out(root, platform);
    if (!/\.txt$/i.test(dest)) {
        var name = (ctx.app.packageName || ctx.app.appName || 'APP').replace(/[^A-Za-z0-9_.-]/g, '_');
        var ver = (ctx.app.appVersion || '0').replace(/[^A-Za-z0-9_.+-]/g, '_');
        dest = path.join(dest, name + '_' + ver + '_' + platform.toUpperCase() + '_BUILD_INFO.txt');
    }
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.writeFileSync(dest, text, 'utf-8');
    return { path: dest, text: text, hasConfig: !!cfg };
}

module.exports = { generate: generate, render: render };

if (require.main === module) {
    var args = parseArgs(process.argv);
    try {
        var r = generate(args);
        console.log('[build-info] -> ' + r.path);
        if (!r.hasConfig) console.log('[build-info] !! khong tim thay fg_main_config.json — file chi co phan version');
        process.exit(0);
    } catch (e) {
        console.error('[build-info] LOI: ' + e.message);
        process.exit(1);
    }
}
