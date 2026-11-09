package com.azkar.mobile;

import android.appwidget.AppWidgetManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;
import java.util.Map;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public final class AzkarMobilePlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
    private Context context;
    private MethodChannel channel;
    private SharedPreferences prayer;
    private SharedPreferences remembrance;
    private SharedPreferences state;

    @Override public void onAttachedToEngine(FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        prayer = context.getSharedPreferences("azkar_prayer_widget", Context.MODE_PRIVATE);
        remembrance = context.getSharedPreferences("azkar_remembrance_widget", Context.MODE_PRIVATE);
        state = context.getSharedPreferences("azkar_mobile_state", Context.MODE_PRIVATE);
        channel = new MethodChannel(binding.getBinaryMessenger(), "azkar/home_widget");
        channel.setMethodCallHandler(this);
    }

    private ComponentName provider(boolean content) {
        return new ComponentName(context.getPackageName(), context.getPackageName() +
            (content ? ".RemembranceWidgetProvider" : ".PrayerWidgetProvider"));
    }

    private void refresh(boolean content) {
        ComponentName component = provider(content);
        int[] ids = AppWidgetManager.getInstance(context).getAppWidgetIds(component);
        if (ids.length == 0) return;
        context.sendBroadcast(new Intent(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
            .setComponent(component).putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids));
    }

    @Override public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        switch (call.method) {
            case "selectLocation": {
                String selection = (String) call.arguments;
                if (selection == null) { result.error("invalid_selection", "Location is required.", null); return; }
                if (!selection.equals(prayer.getString("selection", null))) {
                    prayer.edit().clear().putString("selection", selection).apply();
                    refresh(false);
                }
                result.success(null); return;
            }
            case "setBackgroundGeneration":
                state.edit().putString("generation", (String)call.arguments).apply();
                result.success(null); return;
            case "updateBackground": {
                Map<?, ?> arguments = (Map<?, ?>) call.arguments;
                if (arguments == null || !(arguments.get("generation") instanceof String) || !arguments.get("generation").equals(state.getString("generation", null))) {
                    result.success(null); return;
                }
                prayer.edit().putString("calendar", (String)arguments.get("calendar")).apply();
                refresh(false);
                result.success(null); return;
            }
            case "update":
            case "updateRemembrance": {
                String payload = (String)call.arguments;
                if (payload == null || payload.length() > 300000) {
                    result.error("invalid_payload", "Invalid widget data.", null); return;
                }
                boolean content = call.method.equals("updateRemembrance");
                (content ? remembrance : prayer).edit().putString(content ? "content" : "calendar", payload).apply();
                refresh(content);
                result.success(null); return;
            }
            case "clear":
                prayer.edit().clear().apply(); remembrance.edit().clear().apply(); state.edit().clear().apply();
                refresh(false); refresh(true); result.success(null); return;
            case "requestPin":
            case "requestPinRemembrance": {
                AppWidgetManager manager = AppWidgetManager.getInstance(context);
                boolean supported = Build.VERSION.SDK_INT >= 26 && manager.isRequestPinAppWidgetSupported();
                result.success(supported && manager.requestPinAppWidget(provider(call.method.equals("requestPinRemembrance")), null, null));
                return;
            }
            default: result.notImplemented();
        }
    }
    @Override public void onDetachedFromEngine(FlutterPluginBinding binding) { channel.setMethodCallHandler(null); }
}
