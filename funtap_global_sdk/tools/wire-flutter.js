#!/usr/bin/env node
// wire-flutter.js — đấu dây plugin FGSDK vào project Flutter (chạy sau khi install bat giải nén).
//
// Làm 7 việc, đều IDEMPOTENT (chạy lại không nhân đôi):
//   1. pubspec.yaml            → thêm dependency `funtap_global_sdk: { path: ./funtap_global_sdk }`
//   2. android/app/build.gradle[.kts] → ép minSdk >= 24 (AAR yêu cầu)
//   3. android/gradle.properties      → android.uniquePackageNames=false
//      (AppsFlyer af-android-sdk + purchase-connector CÙNG khai package="com.appsflyer"
//       — mọi version đều vậy, lỗi đóng gói phía AppsFlyer. AGP 9 siết unique namespace
//       nên chặn build; cờ này nới lại.)
//   4. ios/Podfile → `platform :ios, '13.0'` (podspec FGSDK yêu cầu 13.0: ATT + connectedScenes)
//   5. ios/Podfile → chèn vào post_install: ép IPHONEOS_DEPLOYMENT_TARGET >= 13.0 cho MỌI pod
//      (Flutter/CocoaPods để mặc định 12.0 → Firebase/AppLovin bản mới fail link).
//   6. iap_packs.json → gieo bản mẫu vào android/app/src/main/assets/ + ios/Runner/ nếu CHƯA có
//      (server config KHÔNG trả file này — dev tự khai product ID). Có rồi thì KHÔNG đụng.
//   7. build-info-flutter.bat → rải ra root project (chạy SAU khi build để sinh file BUILD INFO
//      cạnh thư mục build, bố cục y hệt bản Unity).
//
// ⚠️ Podfile do lệnh `flutter build ios` sinh ra (không có sẵn sau `flutter create`). Chạy trên
//    Windows thì bước 4/5 sẽ báo "chưa có Podfile" — chạy lại tool này trên Mac sau lần build đầu.
//    Phần iOS phụ thuộc config (Info.plist, resource vào Xcode) nằm ở fetch-config-flutter.js.
//
// Dùng:  node funtap_global_sdk/tools/wire-flutter.js [--project <root>]

'use strict';
var fs = require('fs');
var path = require('path');

var DEP_NAME = 'funtap_global_sdk';
var DEP_PATH = './funtap_global_sdk';
var MIN_SDK = 24;

function parseArgs(argv) {
    var o = {};
    for (var i = 2; i < argv.length; i++) {
        if (argv[i] === '--project') o.project = argv[++i];
    }
    return o;
}

function backup(file) {
    var b = file + '.fgsdkbak';
    if (!fs.existsSync(b)) fs.copyFileSync(file, b);
}

// ── 1. pubspec.yaml ───────────────────────────────────────────────────────────
function wirePubspec(root, log) {
    var file = path.join(root, 'pubspec.yaml');
    if (!fs.existsSync(file)) { log.push('!! Khong thay pubspec.yaml'); return false; }
    var src = fs.readFileSync(file, 'utf-8');

    if (new RegExp('^\\s{2}' + DEP_NAME + ':', 'm').test(src)) {
        log.push('-- pubspec.yaml da co ' + DEP_NAME + ' (bo qua)');
        return true;
    }
    // Chèn ngay sau dòng `dependencies:` ở cột 0 (tránh dev_dependencies).
    var m = /^dependencies:[ \t]*$/m.exec(src);
    if (!m) { log.push('!! Khong tim thay block "dependencies:" trong pubspec.yaml — them tay'); return false; }

    backup(file);
    var insertAt = m.index + m[0].length;
    var block = '\n  ' + DEP_NAME + ':\n    path: ' + DEP_PATH;
    var out = src.slice(0, insertAt) + block + src.slice(insertAt);
    fs.writeFileSync(file, out, 'utf-8');
    log.push('OK pubspec.yaml += ' + DEP_NAME + ' (path: ' + DEP_PATH + ')');
    return true;
}

// ── 2. minSdk >= 24 ───────────────────────────────────────────────────────────
function wireMinSdk(root, log) {
    var candidates = [
        path.join(root, 'android', 'app', 'build.gradle.kts'),
        path.join(root, 'android', 'app', 'build.gradle')
    ];
    var file = candidates.filter(function (p) { return fs.existsSync(p); })[0];
    if (!file) { log.push('!! Khong thay android/app/build.gradle[.kts] — bo qua minSdk'); return; }

    var src = fs.readFileSync(file, 'utf-8');
    // Bắt cả `minSdk = 21`, `minSdkVersion 21`, `minSdk flutter.minSdkVersion`…
    var re = /(minSdkVersion|minSdk)(\s*=\s*|\s+)([A-Za-z0-9_.]+)/;
    var m = re.exec(src);
    if (!m) { log.push('!! Khong tim thay minSdk trong ' + path.basename(file) + ' — dat tay >= 24'); return; }

    var cur = m[3];
    var curNum = parseInt(cur, 10);
    if (!isNaN(curNum) && curNum >= MIN_SDK) {
        log.push('-- minSdk = ' + cur + ' (>= ' + MIN_SDK + ', giu nguyen)');
        return;
    }
    backup(file);
    var out = src.replace(re, m[1] + m[2] + MIN_SDK);
    fs.writeFileSync(file, out, 'utf-8');
    log.push('OK minSdk ' + cur + ' -> ' + MIN_SDK + ' (' + path.basename(file) + ')');
}

// ── 3. gradle.properties: nới kiểm tra unique namespace ───────────────────────
function wireGradleProps(root, log) {
    var file = path.join(root, 'android', 'gradle.properties');
    var KEY = 'android.uniquePackageNames';
    var LINE = KEY + '=false';

    var src = fs.existsSync(file) ? fs.readFileSync(file, 'utf-8') : '';
    if (new RegExp('^\\s*' + KEY.replace(/\./g, '\\.') + '\\s*=', 'm').test(src)) {
        log.push('-- gradle.properties da co ' + KEY + ' (bo qua)');
        return;
    }
    if (fs.existsSync(file)) backup(file);
    var block = (src && !src.endsWith('\n') ? '\n' : '') +
        '\n# AppsFlyer af-android-sdk va purchase-connector CUNG khai package="com.appsflyer"\n' +
        '# (moi version deu vay). AGP 9 siet unique namespace nen chan build -> noi lai.\n' +
        LINE + '\n';
    ensureDirFor(file);
    fs.writeFileSync(file, src + block, 'utf-8');
    log.push('OK gradle.properties += ' + LINE);
}

function ensureDirFor(file) { fs.mkdirSync(path.dirname(file), { recursive: true }); }

// ── 4+5. ios/Podfile ──────────────────────────────────────────────────────────
// CocoaPods chỉ nhận MỘT `post_install` (khai lần 2 là đè lần 1) → KHÔNG append block mới,
// phải chèn vào trong block Flutter đã sinh sẵn. Marker để chạy lại không nhân đôi.
var IOS_MIN = '13.0';
var POD_MARK_BEGIN = '  # --- FGSDK BEGIN (wire-flutter) ---';
var POD_MARK_END = '  # --- FGSDK END ---';

function podDeploymentBlock() {
    return [
        POD_MARK_BEGIN,
        '  # FGSDK can iOS ' + IOS_MIN + ' (ATT + connectedScenes). Pod nao thap hon -> keo len.',
        '  installer.pods_project.targets.each do |fg_t|',
        '    fg_t.build_configurations.each do |fg_c|',
        "      fg_cur = fg_c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'].to_s",
        "      if fg_cur.empty? || fg_cur.to_f < " + IOS_MIN,
        "        fg_c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '" + IOS_MIN + "'",
        '      end',
        '    end',
        '  end',
        POD_MARK_END
    ].join('\n');
}

function wireIosPodfile(root, log) {
    var file = path.join(root, 'ios', 'Podfile');
    if (!fs.existsSync(file)) {
        log.push('!! Chua co ios/Podfile (Flutter sinh luc build iOS dau tien)');
        log.push('   -> Tren Mac: chay `flutter build ios --no-codesign` 1 lan roi chay lai wire-flutter.js');
        return;
    }
    var src = fs.readFileSync(file, 'utf-8');
    var out = src;

    // (4) platform :ios, '13.0' — template Flutter de dong nay dang COMMENT.
    var reActive = /^([ \t]*)platform :ios, *['"]([0-9.]+)['"].*$/m;
    var reCommented = /^[ \t]*#[ \t]*platform :ios, *['"][0-9.]+['"].*$/m;
    var mActive = reActive.exec(out);
    if (mActive) {
        if (parseFloat(mActive[2]) < parseFloat(IOS_MIN)) {
            out = out.replace(reActive, mActive[1] + "platform :ios, '" + IOS_MIN + "'");
            log.push('OK Podfile platform :ios ' + mActive[2] + ' -> ' + IOS_MIN);
        } else {
            log.push('-- Podfile platform :ios = ' + mActive[2] + ' (>= ' + IOS_MIN + ', giu nguyen)');
        }
    } else if (reCommented.test(out)) {
        out = out.replace(reCommented, "platform :ios, '" + IOS_MIN + "'");
        log.push("OK Podfile platform :ios, '" + IOS_MIN + "' (bo comment)");
    } else {
        out = "platform :ios, '" + IOS_MIN + "'\n" + out;
        log.push("OK Podfile += platform :ios, '" + IOS_MIN + "' (dau file)");
    }

    // (5) deployment target cho pod — chen vao post_install san co, khong tao cai thu hai.
    if (out.indexOf(POD_MARK_BEGIN) !== -1) {
        log.push('-- Podfile post_install da co block FGSDK (bo qua)');
    } else {
        var rePost = /^[ \t]*post_install do \|([A-Za-z_][A-Za-z0-9_]*)\|[ \t]*$/m;
        var mPost = rePost.exec(out);
        if (mPost) {
            var block = podDeploymentBlock().replace(/installer\./g, mPost[1] + '.');
            var at = mPost.index + mPost[0].length;
            out = out.slice(0, at) + '\n' + block + out.slice(at);
            log.push('OK Podfile post_install += ep IPHONEOS_DEPLOYMENT_TARGET ' + IOS_MIN);
        } else {
            out = out.replace(/\s*$/, '\n') +
                '\npost_install do |installer|\n' + podDeploymentBlock() + '\nend\n';
            log.push('OK Podfile += post_install (ep IPHONEOS_DEPLOYMENT_TARGET ' + IOS_MIN + ')');
        }
    }

    if (out !== src) { backup(file); fs.writeFileSync(file, out, 'utf-8'); }
}

// ── 6. iap_packs.json ─────────────────────────────────────────────────────────
// Bundle từ server KHÔNG có file này (giống Unity/Cocos) — dev tự khai product ID.
// Thiếu file = IAP init false, mà lỗi lại im lặng → gieo sẵn bản mẫu cho dev sửa.
// iOS: file mới nằm trong ios/Runner/ là chưa đủ, fetch-config-flutter.js sẽ đăng ký nó
// vào Copy Bundle Resources ở bước fetch (chạy ngay sau install theo hướng dẫn của bat).
function seedIapPacks(root, log) {
    var sample = path.join(__dirname, '..', 'config', 'iap_packs.sample.json');
    if (!fs.existsSync(sample)) { log.push('!! Khong thay config/iap_packs.sample.json trong package'); return; }
    [
        path.join(root, 'android', 'app', 'src', 'main', 'assets', 'iap_packs.json'),
        path.join(root, 'ios', 'Runner', 'iap_packs.json')
    ].forEach(function (dest) {
        var rel = path.relative(root, dest).replace(/\\/g, '/');
        if (fs.existsSync(dest)) { log.push('-- ' + rel + ' da co (KHONG ghi de)'); return; }
        ensureDirFor(dest);
        fs.copyFileSync(sample, dest);
        log.push('OK ' + rel + ' (ban MAU — sua product ID cho khop store)');
    });
}

// ── 7. rải build-info-flutter.bat ra root ─────────────────────────────────────
// Bat installer chỉ rải sẵn fetch-config-flutter.* (đã publish, không muốn đổi → khỏi bump BATVER),
// nên script wire rải nốt bat build info. Nó gọi tools/fg-build-info.js trong package.
function dropBuildInfoBat(root, log) {
    var src = path.join(__dirname, 'build-info-flutter.bat');
    if (!fs.existsSync(src)) { log.push('!! Khong thay tools/build-info-flutter.bat trong package'); return; }
    var dest = path.join(root, 'build-info-flutter.bat');
    var same = fs.existsSync(dest) && fs.readFileSync(dest, 'utf-8') === fs.readFileSync(src, 'utf-8');
    if (same) { log.push('-- build-info-flutter.bat (unchanged)'); return; }
    fs.copyFileSync(src, dest);
    log.push('OK build-info-flutter.bat -> root (chay SAU khi build de sinh file BUILD INFO)');
}

// ── main ──────────────────────────────────────────────────────────────────────
(function () {
    var args = parseArgs(process.argv);
    var root = args.project || process.cwd();
    root = root.replace(/^"+|"+$/g, '').replace(/[\\/]+"?$/, '');

    var log = [];
    var ok = wirePubspec(root, log);
    wireMinSdk(root, log);
    wireGradleProps(root, log);
    wireIosPodfile(root, log);
    seedIapPacks(root, log);
    dropBuildInfoBat(root, log);

    log.forEach(function (l) { console.log('   ' + l); });
    if (!ok) {
        console.error('[wire] CHUA XONG — sua tay phan bao !! o tren roi chay lai.');
        process.exit(1);
    }
    console.log('[wire] XONG. Tiep theo: flutter pub get');
    process.exit(0);
})();
