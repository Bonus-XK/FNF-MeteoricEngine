package org.haxe.lime;


import android.content.Context;
import android.content.Intent;
import android.content.res.AssetManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.provider.Settings;
import android.util.DisplayMetrics;
import android.util.Log;
import android.view.KeyCharacterMap;
import android.view.KeyEvent;
import android.view.View;
import android.webkit.MimeTypeMap;
import org.haxe.extension.Extension;
import org.libsdl.app.SDLActivity;

import java.io.File;
import java.util.ArrayList;
import java.util.List;


public class GameActivity extends SDLActivity {


	private static AssetManager assetManager;
	private static List<Extension> extensions;
	private static DisplayMetrics metrics;
	private static Vibrator vibrator;

	public Handler handler;

	public static double getDisplayXDPI () {

		if (metrics == null) {

			metrics = Extension.mainContext.getResources ().getDisplayMetrics ();

		}

		return metrics.xdpi;

	}


	protected String[] getLibraries () {

		return new String[] {
			::foreach ndlls::"::name::",
			::end::"ApplicationMain"
		};

	}


	@Override protected String getMainSharedObject () {

		return "libApplicationMain.so";

	}


	@Override protected String getMainFunction () {

		return "hxcpp_main";

	}


	@Override protected void onActivityResult (int requestCode, int resultCode, Intent data) {

		for (Extension extension : extensions) {

			if (!extension.onActivityResult (requestCode, resultCode, data)) {

				return;

			}

		}

		super.onActivityResult (requestCode, resultCode, data);

	}


	@Override public void onBackPressed () {

		for (Extension extension : extensions) {

			if (!extension.onBackPressed ()) {

				return;

			}

		}

		super.onBackPressed ();

	}


	/** Meteoric：Java 层全局未捕获异常处理器 —— 写 java_crash_*.txt 到 .meteoric/crash/
	 *  （覆盖 OOM/JNI/文件操作等 Java 崩溃：此类崩溃不产生 native 信号，仅靠 last_stage 无法定位） */
	protected void installJavaCrashHandler () {

		Thread.setDefaultUncaughtExceptionHandler (new Thread.UncaughtExceptionHandler () {

			@Override public void uncaughtException (Thread thread, Throwable e) {

				try {

					String base = android.os.Environment.getExternalStorageDirectory ().getAbsolutePath () + "/.meteoric/crash";

					java.io.File dir = new java.io.File (base);

					if (!dir.exists ()) dir.mkdirs ();

					java.io.FileWriter fw = new java.io.FileWriter (base + "/java_crash_" + System.currentTimeMillis () + ".txt");

					fw.write ("============================================================\n");

					fw.write ("  Meteoric Engine - Java Crash Report\n");

					fw.write ("============================================================\n");

					fw.write ("time=" + new java.util.Date () + "\n");

					fw.write ("thread=" + thread.getName () + "\n");

					fw.write ("exception=" + e + "\n");

					Throwable c = e.getCause ();

					int depth = 0;

					while (c != null && depth < 8) { fw.write ("  caused by " + c + "\n"); c = c.getCause (); depth++; }

					for (StackTraceElement se : e.getStackTrace ()) fw.write ("  at " + se + "\n");

					fw.close ();

				} catch (Throwable ignored) {}

				// 终止进程（避免默认处理器重复输出到 logcat 后仍被杀）

				android.os.Process.killProcess (android.os.Process.myPid ());

				System.exit (1);

			}

		});

	}

	protected void onCreate (Bundle state) {

		super.onCreate (state);

		installJavaCrashHandler ();

		assetManager = getAssets ();
		vibrator = (Vibrator)mSingleton.getSystemService (Context.VIBRATOR_SERVICE);
		handler = new Handler ();

		Extension.assetManager = assetManager;
		Extension.callbackHandler = handler;
		Extension.mainActivity = this;
		Extension.mainContext = this;
		Extension.mainView = mLayout;
		Extension.packageName = getApplicationContext ().getPackageName ();

		if (extensions == null) {

			extensions = new ArrayList<Extension> ();
			::if (ANDROID_EXTENSIONS != null)::::foreach ANDROID_EXTENSIONS::
			extensions.add (new ::__current__:: ());::end::::end::

		}

		for (Extension extension : extensions) {

			extension.onCreate (state);

		}

	}


	@Override protected void onDestroy () {

		for (Extension extension : extensions) {

			extension.onDestroy ();

		}

		super.onDestroy ();

	}


	/** Meteoric：低内存/后台告警时向 .meteoric/crash/heartbeat_java.txt 追加时间戳记录
	 *  （OOM 前兆可见；写入失败静默） */
	protected void javaHeartbeatNote (String reason) {

		try {

			String base = android.os.Environment.getExternalStorageDirectory ().getAbsolutePath () + "/.meteoric/crash";

			java.io.File dir = new java.io.File (base);

			if (!dir.exists ()) dir.mkdirs ();

			java.io.FileWriter fw = new java.io.FileWriter (base + "/heartbeat_java.txt", true);

			fw.write (new java.util.Date () + " | " + reason + "\n");

			fw.close ();

		} catch (Throwable ignored) {}

	}

	@Override public void onLowMemory () {

		try { javaHeartbeatNote ("onLowMemory"); } catch (Throwable ignored) {}

		super.onLowMemory ();

		for (Extension extension : extensions) {

			extension.onLowMemory ();

		}

	}

	@Override public void onTrimMemory (int level) {

		try { javaHeartbeatNote ("onTrimMemory level=" + level); } catch (Throwable ignored) {}

		super.onTrimMemory (level);

	}


	@Override protected void onNewIntent (final Intent intent) {

		for (Extension extension : extensions) {

			extension.onNewIntent (intent);

		}

		super.onNewIntent (intent);

	}


	@Override protected void onPause () {

		if (vibrator != null) {

			try {

				vibrator.cancel ();

			} catch (Exception e) {

				// 无 VIBRATE 权限时忽略（防后台崩溃）

			}

		}

		super.onPause ();

		for (Extension extension : extensions) {

			extension.onPause ();

		}

	}


	::if (ANDROID_TARGET_SDK_VERSION >= 23)::
	@Override public void onRequestPermissionsResult (int requestCode, String permissions[], int[] grantResults) {

		for (Extension extension : extensions) {

			if (!extension.onRequestPermissionsResult (requestCode, permissions, grantResults)) {

				return;

			}

		}

		super.onRequestPermissionsResult (requestCode, permissions, grantResults);

	}
	::end::


	@Override protected void onRestart () {

		super.onRestart ();

		for (Extension extension : extensions) {

			extension.onRestart ();

		}

	}


	@Override protected void onResume () {

		super.onResume ();

		for (Extension extension : extensions) {

			extension.onResume ();

		}

	}


	@Override protected void onRestoreInstanceState (Bundle savedState) {

		super.onRestoreInstanceState (savedState);

		for (Extension extension : extensions) {

			extension.onRestoreInstanceState (savedState);

		}

	}


	@Override protected void onSaveInstanceState (Bundle outState) {

		super.onSaveInstanceState (outState);

		for (Extension extension : extensions) {

			extension.onSaveInstanceState (outState);

		}

	}


	@Override protected void onStart () {

		super.onStart ();

		for (Extension extension : extensions) {

			extension.onStart ();

		}

	}


	@Override protected void onStop () {

		super.onStop ();

		for (Extension extension : extensions) {

			extension.onStop ();

		}

	}


	::if (ANDROID_TARGET_SDK_VERSION >= 14)::
	@Override public void onTrimMemory (int level) {

		if (Build.VERSION.SDK_INT >= 14) {

			super.onTrimMemory (level);

			for (Extension extension : extensions) {

				extension.onTrimMemory (level);

			}

		}

	}
	::end::


	public static void openFile (String path) {

		try {

			String extension = path;
			int index = path.lastIndexOf ('.');

			if (index > 0) {

				extension = path.substring (index + 1);

			}

			String mimeType = MimeTypeMap.getSingleton ().getMimeTypeFromExtension (extension);
			File file = new File (path);

			Intent intent = new Intent ();
			intent.setAction (Intent.ACTION_VIEW);
			intent.setDataAndType (Uri.fromFile (file), mimeType);

			Extension.mainActivity.startActivity (intent);

		} catch (Exception e) {

			Log.e ("GameActivity", e.toString ());
			return;

		}

	}


	public static void openURL (String url, String target) {

		Intent browserIntent = new Intent (Intent.ACTION_VIEW).setData (Uri.parse (url));

		try {

			Extension.mainActivity.startActivity (browserIntent);

		} catch (Exception e) {

			Log.e ("GameActivity", e.toString ());
			return;

		}

	}


	// Android 11+：跳转"所有文件访问"权限设置页（供 Haxe 侧 AndroidStorage.openStorageSettings 调用）
	public static void openStorageSettings (String packageName) {

		try {

			Intent intent;

			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {

				intent = new Intent (Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION);
				intent.setData (Uri.parse ("package:" + packageName));

			} else {

				intent = new Intent (Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION);

			}

			Extension.mainActivity.startActivity (intent);

		} catch (Exception e) {

			Log.e ("GameActivity", e.toString ());

		}

	}


	public static void postUICallback (final long handle) {

		Extension.callbackHandler.post (new Runnable () {

			@Override public void run () {

				Lime.onCallback (handle);

			}

		});

	}


	public static void vibrate (int period, int duration) {

		if (vibrator == null || !vibrator.hasVibrator () || period < 0 || duration <= 0) {

			return;

		}

		if (period == 0) {

			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {

				vibrator.vibrate (VibrationEffect.createOneShot (duration, VibrationEffect.DEFAULT_AMPLITUDE));

			} else {

				vibrator.vibrate (duration);

			}

		} else {

			// each period has two halves (vibrator off/vibrator on), and each half requires a separate entry in the array
			int periodMS = (int)Math.ceil (period / 2.0);
			int count = (int)Math.ceil (duration / (double) periodMS);
			long[] pattern = new long[count];

			// the first entry is the delay before vibration starts, so leave it as 0
			for (int i = 1; i < count; i++) {

				pattern[i] = periodMS;

			}

			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {

				vibrator.vibrate (VibrationEffect.createWaveform (pattern, -1));

			} else {

				vibrator.vibrate (pattern, -1);

			}

		}

	}


}
