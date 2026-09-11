package org.shogistudio.platform;

import android.Manifest;
import android.app.Activity;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothManager;
import android.bluetooth.BluetoothServerSocket;
import android.bluetooth.BluetoothSocket;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.os.Build;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.RejectedExecutionException;

/** Android platform access. Match authority and move validation stay in GDScript. */
public final class ShogiPlatform extends GodotPlugin {
    private static final UUID SERVICE = UUID.fromString("aebf9a2f-637d-4cdb-8710-032ebd5c8197");
    private static final int PERMISSIONS = 4711, ENABLE = 4712, DISCOVERABLE = 4713;
    private final ExecutorService io = Executors.newFixedThreadPool(3);
    private final ExecutorService writer = new ThreadPoolExecutor(1, 1, 0, TimeUnit.MILLISECONDS, new ArrayBlockingQueue<Runnable>(32));
    private final ScheduledExecutorService timers = Executors.newSingleThreadScheduledExecutor();
    private final AtomicInteger generation = new AtomicInteger();
    private final AtomicInteger pendingMessages = new AtomicInteger();
    private final Object connectionLock = new Object();
    private volatile BluetoothSocket socket;
    private volatile BluetoothServerSocket server;
    private volatile boolean connected;
    private boolean receiverRegistered;
    private static final int IMPORT_RECORD = 4714, EXPORT_RECORD = 4715;
    private volatile String exportText = "";
    private static final int IMPORT_ANALYSIS = 4716;
    private int analysisRequest;
    private boolean analysisPickerActive;

    public ShogiPlatform(Godot godot) { super(godot); }
    @Override public String getPluginName() { return "ShogiPlatform"; }
    @Override public Set<SignalInfo> getPluginSignals() {
        return new HashSet<>(Arrays.asList(
            new SignalInfo("bluetooth_status", String.class, String.class),
            new SignalInfo("bluetooth_device", String.class),
            new SignalInfo("bluetooth_message", String.class),
            new SignalInfo("record_imported", String.class),
            new SignalInfo("analysis_record_imported", Integer.class, String.class, String.class),
            new SignalInfo("record_exported", Boolean.class)
        ));
    }
    private void status(String state, String message) {
        runOnRenderThread(() -> emitSignal("bluetooth_status", state, message));
    }
    private void connectionStatus(int token, String state, String message) {
        runOnRenderThread(() -> { if (token == generation.get()) emitSignal("bluetooth_status", state, message); });
    }
    private BluetoothAdapter adapter() {
        BluetoothManager manager = (BluetoothManager)getContext().getSystemService(Context.BLUETOOTH_SERVICE);
        return manager == null ? null : manager.getAdapter();
    }
    @UsedByGodot public String enginePath() {
        File file = new File(getContext().getApplicationInfo().nativeLibraryDir, "libyaneuraou.so");
        return file.isFile() ? file.getAbsolutePath() : "";
    }
    @UsedByGodot public boolean bluetoothSupported() { return adapter() != null; }
    private String[] requiredPermissions() {
        return Build.VERSION.SDK_INT >= 31
            ? new String[]{Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_ADVERTISE}
            : new String[]{Manifest.permission.ACCESS_FINE_LOCATION};
    }
    @UsedByGodot public boolean bluetoothPermissionsGranted() {
        for (String permission : requiredPermissions())
            if (getContext().checkSelfPermission(permission) != PackageManager.PERMISSION_GRANTED) return false;
        return true;
    }
    @UsedByGodot public void requestBluetoothPermissions() {
        if (bluetoothPermissionsGranted()) { status("ready", "蓝牙权限已就绪"); return; }
        runOnUiThread(() -> getActivity().requestPermissions(requiredPermissions(), PERMISSIONS));
    }
    @Override public void onMainRequestPermissionsResult(int code, String[] permissions, int[] results) {
        if (code == PERMISSIONS)
            status(bluetoothPermissionsGranted() ? "ready" : "permission_denied", bluetoothPermissionsGranted() ? "蓝牙权限已就绪" : "请在系统设置中允许附近设备权限后重试");
    }
    private boolean usable() {
        if (!bluetoothSupported()) { status("unsupported", "此设备没有蓝牙适配器"); return false; }
        if (!bluetoothPermissionsGranted()) { status("permission_required", "请先允许附近设备权限"); return false; }
        if (!adapter().isEnabled()) { status("disabled", "请先开启蓝牙"); return false; }
        return true;
    }
    @UsedByGodot public void enableBluetooth() {
        if (!bluetoothPermissionsGranted()) { requestBluetoothPermissions(); return; }
        runOnUiThread(() -> {
            try { getActivity().startActivityForResult(new Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE), ENABLE); }
            catch (RuntimeException e) { status("error", "无法打开系统蓝牙设置"); }
        });
    }
    @UsedByGodot public void makeDiscoverable() {
        if (!usable()) return;
        runOnUiThread(() -> {
            try {
                Intent intent = new Intent(BluetoothAdapter.ACTION_REQUEST_DISCOVERABLE);
                intent.putExtra(BluetoothAdapter.EXTRA_DISCOVERABLE_DURATION, 120);
                getActivity().startActivityForResult(intent, DISCOVERABLE);
            } catch (RuntimeException e) { status("error", "无法打开蓝牙可发现设置"); }
        });
    }
    @Override public void onMainActivityResult(int code, int result, Intent data) {
        if (code == IMPORT_ANALYSIS) {
            final int request = analysisRequest;
            analysisPickerActive = false;
            if (result != Activity.RESULT_OK || data == null || data.getData() == null) {
                analysisResult(request, "", "");
                return;
            }
            final android.net.Uri uri = data.getData();
            io.execute(() -> {
                String text = "", error = "";
                try (InputStream input = getActivity().getContentResolver().openInputStream(uri)) {
                    text = AnalysisRecordText.read(input);
                    if (text.isEmpty()) error = "棋谱文件为空。";
                } catch (Exception failure) {
                    error = "棋谱读取失败：请使用不超过 2 MiB 的 UTF-8 或 Shift JIS 文件。";
                }
                analysisResult(request, text, error);
            });
            return;
        }
        if ((code == IMPORT_RECORD || code == EXPORT_RECORD) && result == Activity.RESULT_OK && data != null && data.getData() != null) {
            android.net.Uri uri = data.getData();
            io.execute(() -> {
                if (code == IMPORT_RECORD) {
                    String text = "";
                    try (InputStream input = getActivity().getContentResolver().openInputStream(uri); ByteArrayOutputStream bytes = new ByteArrayOutputStream()) {
                        byte[] buffer = new byte[8192]; int count;
                        while ((count = input.read(buffer)) != -1) {
                            if (bytes.size() + count > 20000000) throw new IOException("Record too large");
                            bytes.write(buffer, 0, count);
                        }
                        text = new String(bytes.toByteArray(), StandardCharsets.UTF_8);
                    } catch (Exception ignored) { }
                    final String record = text;
                    runOnRenderThread(() -> emitSignal("record_imported", record));
                } else {
                    boolean success = false;
                    try (java.io.OutputStream output = getActivity().getContentResolver().openOutputStream(uri, "wt")) {
                        output.write(exportText.getBytes(StandardCharsets.UTF_8));
                        output.flush(); success = true;
                    } catch (Exception ignored) { }
                    exportText = "";
                    final boolean saved = success;
                    runOnRenderThread(() -> emitSignal("record_exported", saved));
                }
            });
            return;
        }
        if (code == ENABLE) status(result == Activity.RESULT_OK ? "ready" : "disabled", result == Activity.RESULT_OK ? "蓝牙已开启" : "尚未开启蓝牙");
        if (code == DISCOVERABLE) status(result > 0 ? "discoverable" : "ready", result > 0 ? "附近设备现在可以找到你" : "未开启可发现模式");
    }
    @UsedByGodot public boolean isDarkMode() {
        return (getActivity().getResources().getConfiguration().uiMode & android.content.res.Configuration.UI_MODE_NIGHT_MASK) != android.content.res.Configuration.UI_MODE_NIGHT_NO;
    }
    @UsedByGodot public void setColorMode(String mode) {
        getActivity().getSharedPreferences("shogi_appearance", Context.MODE_PRIVATE).edit().putString("mode", mode).apply();
    }
    @UsedByGodot public void pickRecord() {
        getActivity().runOnUiThread(() -> {
            Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*");
            try { getActivity().startActivityForResult(intent, IMPORT_RECORD); }
            catch (RuntimeException e) { runOnRenderThread(() -> emitSignal("record_imported", "")); }
        });
    }
    private void analysisResult(int request, String text, String error) {
        runOnRenderThread(() -> emitSignal("analysis_record_imported", request, text, error));
    }
    @UsedByGodot public void pickAnalysisRecord(int request) {
        runOnUiThread(() -> {
            if (analysisPickerActive) {
                analysisResult(request, "", "请先关闭已打开的文件选择器。");
                return;
            }
            analysisRequest = request;
            analysisPickerActive = true;
            try {
                Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT)
                        .addCategory(Intent.CATEGORY_OPENABLE).setType("*/*");
                getActivity().startActivityForResult(intent, IMPORT_ANALYSIS);
            } catch (RuntimeException failure) {
                analysisPickerActive = false;
                analysisResult(request, "", "无法打开文件选择器。");
            }
        });
    }
    @UsedByGodot public void exportRecord(String text) {
        exportText(text, "shogi-record.json");
    }
    @UsedByGodot public void exportText(String text, String filename) {
        if (text.length() > 20000000) { runOnRenderThread(() -> emitSignal("record_exported", false)); return; }
        final String safeName = filename.replaceAll("[^a-zA-Z0-9._-]", "_");
        exportText = text;
        getActivity().runOnUiThread(() -> {
            Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType(safeName.endsWith(".json") ? "application/json" : "text/plain").putExtra(Intent.EXTRA_TITLE, safeName);
            try { getActivity().startActivityForResult(intent, EXPORT_RECORD); }
            catch (RuntimeException e) { runOnRenderThread(() -> emitSignal("record_exported", false)); }
        });
    }
    private String deviceJson(BluetoothDevice device) {
        JSONObject out = new JSONObject();
        try {
            out.put("address", device.getAddress());
            out.put("name", device.getName() == null ? "未命名设备" : device.getName());
            out.put("paired", device.getBondState() == BluetoothDevice.BOND_BONDED);
        } catch (Exception e) { return "{}"; }
        return out.toString();
    }
    @UsedByGodot public String pairedDevices() {
        JSONArray out = new JSONArray();
        if (!usable()) return out.toString();
        try {
            for (BluetoothDevice device : adapter().getBondedDevices()) out.put(new JSONObject(deviceJson(device)));
        } catch (Exception e) { status("error", "无法读取已配对设备"); }
        return out.toString();
    }
    private final BroadcastReceiver receiver = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) {
            if (BluetoothDevice.ACTION_FOUND.equals(intent.getAction())) {
                BluetoothDevice device = intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE);
                if (device != null && bluetoothPermissionsGranted()) {
                    String json = deviceJson(device);
                    runOnRenderThread(() -> emitSignal("bluetooth_device", json));
                }
            } else if (BluetoothAdapter.ACTION_DISCOVERY_FINISHED.equals(intent.getAction())) {
                status("scan_finished", "搜索完成");
            }
        }
    };
    @UsedByGodot public void scanDevices() {
        if (!usable()) return;
        runOnUiThread(() -> {
            try {
                if (!receiverRegistered) {
                    IntentFilter filter = new IntentFilter(BluetoothDevice.ACTION_FOUND);
                    filter.addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED);
                    if (Build.VERSION.SDK_INT >= 33) getContext().registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED);
                    else getContext().registerReceiver(receiver, filter);
                    receiverRegistered = true;
                }
                adapter().cancelDiscovery();
                status(adapter().startDiscovery() ? "scanning" : "error", "正在搜索附近设备");
            } catch (RuntimeException e) { status("error", "蓝牙搜索失败，请检查系统权限"); }
        });
    }
    @UsedByGodot public void stopScan() {
        try { if (adapter() != null && bluetoothPermissionsGranted()) adapter().cancelDiscovery(); }
        catch (RuntimeException ignored) { }
    }
    @UsedByGodot public void hostBluetooth() {
        if (!usable()) return;
        disconnectBluetooth();
        final int token = generation.get();
        io.execute(() -> {
            BluetoothServerSocket listener = null;
            try {
                listener = adapter().listenUsingRfcommWithServiceRecord("Shogi Studio", SERVICE);
                synchronized (connectionLock) {
                    if (token != generation.get()) { listener.close(); return; }
                    server = listener;
                }
                connectionStatus(token, "listening", "等待对手连接");
                BluetoothSocket accepted = listener.accept();
                listener.close();
                synchronized (connectionLock) { if (server == listener) server = null; }
                attach(accepted, token);
            } catch (IOException | SecurityException e) {
                connectionStatus(token, "error", "无法等待蓝牙连接，请重试");
            } finally {
                try { if (listener != null) listener.close(); } catch (IOException ignored) { }
            }
        });
    }
    @UsedByGodot public void connectBluetooth(String address) {
        if (!usable() || !BluetoothAdapter.checkBluetoothAddress(address)) { status("error", "蓝牙地址无效"); return; }
        disconnectBluetooth();
        stopScan();
        final int token = generation.get();
        io.execute(() -> {
            BluetoothSocket pending = null;
            try {
                pending = adapter().getRemoteDevice(address).createRfcommSocketToServiceRecord(SERVICE);
                synchronized (connectionLock) {
                    if (token != generation.get()) { pending.close(); return; }
                    socket = pending;
                }
                connectionStatus(token, "connecting", "正在连接；如系统提示，请确认配对");
                final BluetoothSocket timedSocket = pending;
                timers.schedule(() -> {
                    if (token == generation.get() && !connected) {
                        try { timedSocket.close(); } catch (IOException ignored) { }
                    }
                }, 30, TimeUnit.SECONDS);
                pending.connect();
                attach(pending, token);
            } catch (IOException | SecurityException e) {
                connectionStatus(token, "error", "蓝牙连接失败或超时，请让对手先创建对局");
            } finally {
                if (pending != null) closeOwnedSocket(pending);
            }
        });
    }
    private void closeOwnedSocket(BluetoothSocket previous) {
        try { previous.close(); } catch (IOException ignored) { }
        synchronized (connectionLock) {
            if (socket == previous) { connected = false; socket = null; }
        }
    }
    private void attach(BluetoothSocket accepted, int token) throws IOException {
        try {
            InputStream input = accepted.getInputStream();
            synchronized (connectionLock) {
                if (token != generation.get()) return;
                socket = accepted;
                connected = true;
            }
            connectionStatus(token, "connected", "蓝牙已连接");
            ByteArrayOutputStream line = new ByteArrayOutputStream();
            byte[] bytes = new byte[4096];
            int count;
            while (token == generation.get() && (count = input.read(bytes)) != -1) {
                for (int i = 0; i < count; i++) {
                    if (bytes[i] == '\n') {
                        String message = new String(line.toByteArray(), StandardCharsets.UTF_8);
                        line.reset();
                        if (pendingMessages.incrementAndGet() > 128) {
                            pendingMessages.decrementAndGet();
                            throw new IOException("Too many pending messages");
                        }
                        runOnRenderThread(() -> {
                            try { if (token == generation.get()) emitSignal("bluetooth_message", message); }
                            finally { pendingMessages.decrementAndGet(); }
                        });
                    } else {
                        line.write(bytes[i]);
                        if (line.size() > 65536) throw new IOException("Message too large");
                    }
                }
            }
        } finally {
            closeOwnedSocket(accepted);
            connectionStatus(token, "disconnected", "蓝牙已断开，可以重新连接");
        }
    }
    @UsedByGodot public boolean sendBluetooth(String message) {
        final BluetoothSocket current = socket;
        final int token = generation.get();
        byte[] payload = (message + "\n").getBytes(StandardCharsets.UTF_8);
        if (!connected || current == null || payload.length > 65537 || message.contains("\n") || message.contains("\r")) return false;
        try {
            writer.execute(() -> {
                if (token != generation.get()) return;
                try { current.getOutputStream().write(payload); current.getOutputStream().flush(); }
                catch (IOException e) {
                    synchronized (connectionLock) {
                        if (token == generation.get()) { connected = false; socket = null; }
                    }
                    try { current.close(); } catch (IOException ignored) { }
                    connectionStatus(token, "disconnected", "蓝牙发送失败，请重新连接");
                }
            });
        } catch (RejectedExecutionException e) { return false; }
        return true;
    }
    @UsedByGodot public void disconnectBluetooth() {
        BluetoothSocket previous;
        BluetoothServerSocket listener;
        synchronized (connectionLock) {
            generation.incrementAndGet();
            connected = false;
            previous = socket;
            listener = server;
            socket = null;
            server = null;
        }
        try { if (previous != null) previous.close(); } catch (IOException ignored) { }
        try { if (listener != null) listener.close(); } catch (IOException ignored) { }
    }
    @Override public void onMainDestroy() {
        disconnectBluetooth();
        stopScan();
        if (receiverRegistered) { getContext().unregisterReceiver(receiver); receiverRegistered = false; }
        io.shutdownNow(); writer.shutdownNow(); timers.shutdownNow();
    }
}
