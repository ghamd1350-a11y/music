#!/usr/bin/env bash
# Generates a native Android project in ./android-app from index.html + icon-192.png
set -e
P=android-app
J=$P/app/src/main/java/com/maktabti/app
rm -rf "$P"
mkdir -p "$J" "$P/app/src/main/assets" "$P/app/src/main/res/mipmap-xxxhdpi"
cp index.html "$P/app/src/main/assets/index.html"
cp icon-192.png "$P/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png"

cat > "$P/settings.gradle" <<'EOF_A'
pluginManagement {
    repositories { google(); mavenCentral(); gradlePluginPortal() }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories { google(); mavenCentral() }
}
rootProject.name = "Maktabti"
include ':app'
EOF_A

cat > "$P/build.gradle" <<'EOF_B'
plugins { id 'com.android.application' version '8.2.2' apply false }
EOF_B

cat > "$P/gradle.properties" <<'EOF_C'
android.useAndroidX=true
org.gradle.jvmargs=-Xmx2048m
EOF_C

cat > "$P/app/build.gradle" <<'EOF_D'
plugins { id 'com.android.application' }
android {
    namespace 'com.maktabti.app'
    compileSdk 34
    defaultConfig {
        applicationId "com.maktabti.app"
        minSdk 24
        targetSdk 34
        versionCode 1
        versionName "1.0"
    }
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
}
dependencies {
    implementation 'androidx.webkit:webkit:1.9.0'
    implementation 'androidx.core:core:1.12.0'
}
EOF_D

cat > "$P/app/src/main/AndroidManifest.xml" <<'EOF_E'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <application
        android:label="مكتبتي"
        android:icon="@mipmap/ic_launcher"
        android:supportsRtl="true"
        android:allowBackup="true"
        android:theme="@android:style/Theme.DeviceDefault.NoActionBar">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTask"
            android:windowSoftInputMode="adjustResize"
            android:configChanges="orientation|screenSize|keyboardHidden|smallestScreenSize|screenLayout|uiMode|layoutDirection">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <service
            android:name=".PlayerService"
            android:exported="false"
            android:foregroundServiceType="mediaPlayback"/>
    </application>
</manifest>
EOF_E

cat > "$J/MainActivity.java" <<'EOF_F'
package com.maktabti.app;

import android.Manifest;
import android.app.Activity;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.graphics.Color;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.webkit.JavascriptInterface;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import androidx.core.content.ContextCompat;
import androidx.webkit.WebViewAssetLoader;

public class MainActivity extends Activity {
    public static final String ACT_CMD = "com.maktabti.app.CMD";
    private WebView web;
    private ValueCallback<Uri[]> chooser;

    private final BroadcastReceiver rx = new BroadcastReceiver() {
        @Override
        public void onReceive(Context c, Intent i) {
            String cmd = i.getStringExtra("cmd");
            if (cmd != null && web != null) {
                web.evaluateJavascript("window.__cmd&&window.__cmd('" + cmd + "')", null);
            }
        }
    };

    public class Bridge {
        @JavascriptInterface
        public void state(final boolean playing, final String title, final String artist) {
            runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    Intent i = new Intent(MainActivity.this, PlayerService.class);
                    i.putExtra("playing", playing);
                    i.putExtra("title", title);
                    i.putExtra("artist", artist);
                    try {
                        ContextCompat.startForegroundService(MainActivity.this, i);
                    } catch (Exception e) {
                        // ignore
                    }
                }
            });
        }
    }

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        getWindow().setStatusBarColor(Color.parseColor("#121212"));
        getWindow().setNavigationBarColor(Color.parseColor("#121212"));
        if (Build.VERSION.SDK_INT >= 33) {
            requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, 1);
        }
        ContextCompat.registerReceiver(this, rx, new IntentFilter(ACT_CMD), ContextCompat.RECEIVER_NOT_EXPORTED);

        web = new WebView(this);
        setContentView(web);
        web.setBackgroundColor(Color.parseColor("#121212"));
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setAllowFileAccess(false);
        web.addJavascriptInterface(new Bridge(), "Native");

        final WebViewAssetLoader loader = new WebViewAssetLoader.Builder()
                .addPathHandler("/assets/", new WebViewAssetLoader.AssetsPathHandler(this))
                .build();
        web.setWebViewClient(new WebViewClient() {
            @Override
            public WebResourceResponse shouldInterceptRequest(WebView v, WebResourceRequest r) {
                return loader.shouldInterceptRequest(r.getUrl());
            }
        });
        web.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onShowFileChooser(WebView w, ValueCallback<Uri[]> cb, FileChooserParams p) {
                if (chooser != null) chooser.onReceiveValue(null);
                chooser = cb;
                boolean img = false;
                String[] t = p.getAcceptTypes();
                if (t != null) {
                    for (String x : t) {
                        if (x != null && x.startsWith("image")) img = true;
                    }
                }
                Intent i = new Intent(Intent.ACTION_GET_CONTENT);
                i.addCategory(Intent.CATEGORY_OPENABLE);
                i.setType("*/*");
                i.putExtra(Intent.EXTRA_MIME_TYPES, img ? new String[]{"image/*"} : new String[]{"audio/*", "video/*"});
                i.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, p.getMode() == FileChooserParams.MODE_OPEN_MULTIPLE);
                try {
                    startActivityForResult(i, 7);
                } catch (Exception e) {
                    chooser = null;
                    return false;
                }
                return true;
            }
        });
        web.loadUrl("https://appassets.androidplatform.net/assets/index.html");
    }

    @Override
    protected void onActivityResult(int req, int res, Intent data) {
        super.onActivityResult(req, res, data);
        if (req == 7 && chooser != null) {
            chooser.onReceiveValue(WebChromeClient.FileChooserParams.parseResult(res, data));
            chooser = null;
        }
    }

    @Override
    public void onBackPressed() {
        web.evaluateJavascript("(window.__back?window.__back():false)", new ValueCallback<String>() {
            @Override
            public void onReceiveValue(String v) {
                if (!"true".equals(v)) moveTaskToBack(true);
            }
        });
    }

    @Override
    protected void onDestroy() {
        try { unregisterReceiver(rx); } catch (Exception e) { }
        stopService(new Intent(this, PlayerService.class));
        if (web != null) web.destroy();
        super.onDestroy();
    }
}
EOF_F

cat > "$J/PlayerService.java" <<'EOF_G'
package com.maktabti.app;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.IBinder;
import android.os.PowerManager;

public class PlayerService extends Service {
    private static final String CH = "play";
    private PowerManager.WakeLock wl;

    @Override
    public IBinder onBind(Intent i) {
        return null;
    }

    private PendingIntent cmd(String c, int code) {
        Intent i = new Intent(MainActivity.ACT_CMD).setPackage(getPackageName()).putExtra("cmd", c);
        return PendingIntent.getBroadcast(this, code, i, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
    }

    @Override
    public int onStartCommand(Intent in, int flags, int startId) {
        String title = "مكتبتي";
        String artist = "";
        boolean playing = false;
        if (in != null) {
            if (in.getStringExtra("title") != null && !in.getStringExtra("title").isEmpty()) title = in.getStringExtra("title");
            if (in.getStringExtra("artist") != null) artist = in.getStringExtra("artist");
            playing = in.getBooleanExtra("playing", false);
        }
        NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(new NotificationChannel(CH, "التشغيل", NotificationManager.IMPORTANCE_LOW));
        }
        Intent open = new Intent(this, MainActivity.class).setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_REORDER_TO_FRONT);
        PendingIntent pi = PendingIntent.getActivity(this, 0, open, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        Notification.Builder nb = Build.VERSION.SDK_INT >= 26 ? new Notification.Builder(this, CH) : new Notification.Builder(this);
        nb.setSmallIcon(android.R.drawable.ic_media_play)
                .setContentTitle(title)
                .setContentText(artist)
                .setContentIntent(pi)
                .setOngoing(true)
                .setShowWhen(false)
                .addAction(android.R.drawable.ic_media_previous, "السابق", cmd("prev", 1))
                .addAction(playing ? android.R.drawable.ic_media_pause : android.R.drawable.ic_media_play, playing ? "إيقاف" : "تشغيل", cmd("pp", 2))
                .addAction(android.R.drawable.ic_media_next, "التالي", cmd("next", 3))
                .setStyle(new Notification.MediaStyle().setShowActionsInCompactView(0, 1, 2));
        Notification n = nb.build();
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(1, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK);
        } else {
            startForeground(1, n);
        }
        if (wl == null) {
            PowerManager pm = (PowerManager) getSystemService(POWER_SERVICE);
            wl = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "maktabti:play");
        }
        if (playing && !wl.isHeld()) wl.acquire();
        if (!playing && wl.isHeld()) wl.release();
        return START_NOT_STICKY;
    }

    @Override
    public void onDestroy() {
        if (wl != null && wl.isHeld()) wl.release();
        super.onDestroy();
    }
}
EOF_G
echo "Generated $P"
