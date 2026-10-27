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
    signingConfigs {
        debug {
            storeFile file('debug.keystore')
            storePassword 'android'
            keyAlias 'androiddebugkey'
            keyPassword 'android'
        }
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
    <uses-permission android:name="android.permission.INTERNET"/>
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
        public void state(final boolean playing, final String title, final String artist, final long pos, final long dur, final String art) {
            runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    Intent i = new Intent(MainActivity.this, PlayerService.class);
                    i.putExtra("playing", playing);
                    i.putExtra("title", title);
                    i.putExtra("artist", artist);
                    i.putExtra("pos", pos);
                    i.putExtra("dur", dur);
                    i.putExtra("art", art);
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
                Uri u = r.getUrl();
                String host = u.getHost() == null ? "" : u.getHost();
                if ((host.equals("archive.org") || host.endsWith(".archive.org")) && "GET".equals(r.getMethod())) {
                    try {
                        java.net.HttpURLConnection c = (java.net.HttpURLConnection) new java.net.URL(u.toString()).openConnection();
                        c.setInstanceFollowRedirects(true);
                        c.setConnectTimeout(15000);
                        c.setReadTimeout(30000);
                        c.setRequestProperty("User-Agent", "Maktabti/1.0");
                        int code = c.getResponseCode();
                        String ct = c.getContentType();
                        String mime = ct == null ? "application/octet-stream" : ct.split(";")[0].trim();
                        java.util.Map<String, String> hd = new java.util.HashMap<String, String>();
                        hd.put("Access-Control-Allow-Origin", "*");
                        long len = c.getContentLengthLong();
                        if (len >= 0 && (mime.startsWith("audio") || mime.startsWith("video") || mime.equals("application/octet-stream"))) {
                            hd.put("Content-Length", String.valueOf(len));
                        }
                        java.io.InputStream in = code >= 400 ? c.getErrorStream() : c.getInputStream();
                        if (in == null || code < 200 || (code >= 300 && code < 400)) return null;
                        return new WebResourceResponse(mime, null, code, "OK", hd, in);
                    } catch (Exception e) {
                        return null;
                    }
                }
                return loader.shouldInterceptRequest(u);
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
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.media.MediaMetadata;
import android.media.session.MediaSession;
import android.media.session.PlaybackState;
import android.os.Build;
import android.os.IBinder;
import android.os.PowerManager;
import android.util.Base64;

public class PlayerService extends Service {
    private static final String CH = "play";
    private PowerManager.WakeLock wl;
    private MediaSession session;
    private String lastArt = "";
    private Bitmap lastBmp;

    @Override
    public IBinder onBind(Intent i) {
        return null;
    }

    private void send(String c) {
        sendBroadcast(new Intent(MainActivity.ACT_CMD).setPackage(getPackageName()).putExtra("cmd", c));
    }

    private PendingIntent cmd(String c, int code) {
        Intent i = new Intent(MainActivity.ACT_CMD).setPackage(getPackageName()).putExtra("cmd", c);
        return PendingIntent.getBroadcast(this, code, i, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
    }

    @Override
    public void onCreate() {
        super.onCreate();
        session = new MediaSession(this, "maktabti");
        session.setCallback(new MediaSession.Callback() {
            @Override public void onPlay() { send("play"); }
            @Override public void onPause() { send("pause"); }
            @Override public void onSkipToNext() { send("next"); }
            @Override public void onSkipToPrevious() { send("prev"); }
            @Override public void onSeekTo(long pos) { send("seek:" + pos); }
        });
        session.setActive(true);
    }

    @Override
    public int onStartCommand(Intent in, int flags, int startId) {
        String title = "مكتبتي";
        String artist = "";
        String art = "";
        boolean playing = false;
        long pos = 0;
        long dur = 0;
        if (in != null) {
            if (in.getStringExtra("title") != null && !in.getStringExtra("title").isEmpty()) title = in.getStringExtra("title");
            if (in.getStringExtra("artist") != null) artist = in.getStringExtra("artist");
            if (in.getStringExtra("art") != null) art = in.getStringExtra("art");
            playing = in.getBooleanExtra("playing", false);
            pos = in.getLongExtra("pos", 0);
            dur = in.getLongExtra("dur", 0);
        }
        if (!art.equals(lastArt)) {
            lastArt = art;
            lastBmp = null;
            if (!art.isEmpty()) {
                try {
                    byte[] b = Base64.decode(art, Base64.DEFAULT);
                    lastBmp = BitmapFactory.decodeByteArray(b, 0, b.length);
                } catch (Exception e) {
                    lastBmp = null;
                }
            }
        }

        MediaMetadata.Builder mb = new MediaMetadata.Builder()
                .putString(MediaMetadata.METADATA_KEY_TITLE, title)
                .putString(MediaMetadata.METADATA_KEY_ARTIST, artist)
                .putLong(MediaMetadata.METADATA_KEY_DURATION, dur);
        if (lastBmp != null) {
            mb.putBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART, lastBmp);
            mb.putBitmap(MediaMetadata.METADATA_KEY_ART, lastBmp);
        }
        session.setMetadata(mb.build());
        long actions = PlaybackState.ACTION_PLAY | PlaybackState.ACTION_PAUSE | PlaybackState.ACTION_PLAY_PAUSE
                | PlaybackState.ACTION_SKIP_TO_NEXT | PlaybackState.ACTION_SKIP_TO_PREVIOUS | PlaybackState.ACTION_SEEK_TO;
        session.setPlaybackState(new PlaybackState.Builder()
                .setActions(actions)
                .setState(playing ? PlaybackState.STATE_PLAYING : PlaybackState.STATE_PAUSED, pos, playing ? 1f : 0f)
                .build());

        NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(new NotificationChannel(CH, "التشغيل", NotificationManager.IMPORTANCE_LOW));
        }
        Intent open = new Intent(this, MainActivity.class).setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_REORDER_TO_FRONT);
        PendingIntent pi = PendingIntent.getActivity(this, 0, open, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        Notification.Builder nb = Build.VERSION.SDK_INT >= 26 ? new Notification.Builder(this, CH) : new Notification.Builder(this);
        nb.setSmallIcon(R.drawable.ic_stat)
                .setContentTitle(title)
                .setContentText(artist)
                .setContentIntent(pi)
                .setOngoing(true)
                .setShowWhen(false)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .addAction(android.R.drawable.ic_media_previous, "السابق", cmd("prev", 1))
                .addAction(playing ? android.R.drawable.ic_media_pause : android.R.drawable.ic_media_play, playing ? "إيقاف" : "تشغيل", cmd("pp", 2))
                .addAction(android.R.drawable.ic_media_next, "التالي", cmd("next", 3))
                .setStyle(new Notification.MediaStyle()
                        .setMediaSession(session.getSessionToken())
                        .setShowActionsInCompactView(0, 1, 2));
        if (lastBmp != null) nb.setLargeIcon(lastBmp);
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
        if (session != null) {
            session.setActive(false);
            session.release();
        }
        super.onDestroy();
    }
}
EOF_G
mkdir -p "$P/app/src/main/res/drawable"
cat > "$P/app/src/main/res/drawable/ic_stat.xml" <<'EOF_H'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#FFFFFF" android:pathData="M12,2C6.48,2 2,6.48 2,12s4.48,10 10,10 10,-4.48 10,-10S17.52,2 12,2zM10,16.5v-9l6,4.5 -6,4.5z"/>
</vector>
EOF_H
base64 -d > "$P/app/debug.keystore" <<'EOF_K'
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
EOF_K
echo "Generated $P"
