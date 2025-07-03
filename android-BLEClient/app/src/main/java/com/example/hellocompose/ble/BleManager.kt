package com.example.hellocompose.ble

import android.Manifest
import android.annotation.SuppressLint
import android.app.Application
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.util.Log
import androidx.annotation.RequiresPermission
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Manages BLE operations for temperature sensing.
 * Handles device scanning, connection, and data reading from a BLE temperature sensor.
 *
 * Features:
 * - Automatic scanning for devices with matching SERVICE_UUID
 * - Connection management with timeout and error handling
 * - Temperature reading via characteristic read and notifications
 * - Connection state monitoring
 *
 * @param app Application context required for BLE operations
 */
class BleManager(private val app: Application) {
    // StateFlow for temperature updates, null when no data available
    private val _temperature = MutableStateFlow<Float?>(null)
    val temperature: StateFlow<Float?> = _temperature

    // StateFlow for connection state updates
    private val _connectionState = MutableStateFlow<BleConnectionState>(BleConnectionState.Disconnected)
    val connectionState: StateFlow<BleConnectionState> = _connectionState

    // GATT connection instance
    private var gatt: BluetoothGatt? = null

    // Bluetooth system services
    private val bluetoothManager by lazy {
        app.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    }
    private val bluetoothAdapter by lazy { bluetoothManager.adapter }
    private val scanner get() = bluetoothAdapter?.bluetoothLeScanner

    // Handler for managing scan timeout
    private val handler = Handler(Looper.getMainLooper())
    private val SCAN_TIMEOUT = 10000L // 10 seconds

    /**
     * Start BLE scan and connect to the first device advertising our service UUID.
     * Requires Bluetooth permissions.
     */
    @RequiresPermission(allOf = [
        Manifest.permission.BLUETOOTH_SCAN,
        Manifest.permission.BLUETOOTH_CONNECT
    ])
    fun connect() {
        // Check if BLE is available and enabled
        if (bluetoothAdapter == null || !bluetoothAdapter?.isEnabled!!) {
            _connectionState.value = BleConnectionState.Error("Bluetooth not available or not enabled")
            return
        }

        val filter = ScanFilter.Builder()
            .setServiceUuid(ParcelUuid(SERVICE_UUID))
            .build()
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()

        _connectionState.value = BleConnectionState.Scanning
        Log.i("BLE", "Starting scan for service: $SERVICE_UUID")
        scanner?.startScan(listOf(filter), settings, scanCallback)

        // Set scan timeout
        handler.postDelayed({
            if (_connectionState.value == BleConnectionState.Scanning) {
                scanner?.stopScan(scanCallback)
                _connectionState.value = BleConnectionState.Error("Scan timeout - no devices found")
            }
        }, SCAN_TIMEOUT)
    }

    /**
     * Cleans up all BLE resources and connections.
     * Should be called when the BLE connection is no longer needed.
     * Handles:
     * - Stopping ongoing scans
     * - Closing GATT connection
     * - Clearing handlers and state
     */
    @SuppressLint("MissingPermission")
    fun disconnect() {
        handler.removeCallbacksAndMessages(null)
        scanner?.stopScan(scanCallback)
        gatt?.close()
        gatt = null
        _connectionState.value = BleConnectionState.Disconnected
        _temperature.value = null
    }

    /**
     * Callback for BLE scanning operations.
     * Handles device discovery and initiates connection.
     */
    private val scanCallback = object : ScanCallback() {
        @SuppressLint("MissingPermission")
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            Log.d("BLE", "Device found: ${result.device.address}")
            scanner?.stopScan(this)
            handler.removeCallbacksAndMessages(null)

            _connectionState.value = BleConnectionState.Connecting
            result.device.connectGatt(app, false, gattCallback)
        }

        override fun onScanFailed(errorCode: Int) {
            Log.e("BLE", "Scan failed: $errorCode")
            _connectionState.value = BleConnectionState.Error("Scan failed with error: $errorCode")
        }
    }

    /**
     * Callback for GATT operations.
     * Handles:
     * - Connection state changes
     * - Service discovery
     * - Characteristic reading
     * - Notifications
     */
    private val gattCallback = object : BluetoothGattCallback() {
        @SuppressLint("MissingPermission")
        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
            Log.i("BLE", "onConnectionStateChange: status=$status, newState=$newState")

            when (newState) {
                BluetoothProfile.STATE_CONNECTED -> {
                    if (status == BluetoothGatt.GATT_SUCCESS) {
                        gatt = g
                        _connectionState.value = BleConnectionState.Connected
                        g.discoverServices()
                    } else {
                        _connectionState.value = BleConnectionState.Error("Connection failed with status: $status")
                        g.close()
                    }
                }
                BluetoothProfile.STATE_DISCONNECTED -> {
                    _connectionState.value = BleConnectionState.Disconnected
                    _temperature.value = null
                    g.close()
                }
            }
        }

        @SuppressLint("MissingPermission")
        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
            if (status != BluetoothGatt.GATT_SUCCESS) {
                _connectionState.value = BleConnectionState.Error("Service discovery failed")
                return
            }

            val characteristic = g.getService(SERVICE_UUID)?.getCharacteristic(TEMP_CHAR_UUID)
            characteristic?.let { char ->
                // Check if characteristic supports notifications
                if (char.properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY != 0) {
                    g.setCharacteristicNotification(char, true)
                }
                // Read initial value
                g.readCharacteristic(char)
            } ?: run {
                _connectionState.value = BleConnectionState.Error("Required characteristic not found")
                g.close()
            }
        }

        override fun onCharacteristicRead(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
            handleCharacteristicValue(characteristic, status)
        }

        override fun onCharacteristicChanged(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            handleCharacteristicValue(characteristic, BluetoothGatt.GATT_SUCCESS)
        }

        /**
         * Processes characteristic value updates.
         * Converts raw bytes to temperature value and updates state.
         *
         * @param characteristic The characteristic containing temperature data
         * @param status The status of the read operation
         */
        private fun handleCharacteristicValue(characteristic: BluetoothGattCharacteristic, status: Int) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                val bytes = characteristic.value
                if (bytes != null && bytes.size >= 4) {
                    val temp = ByteBuffer
                        .wrap(bytes)
                        .order(ByteOrder.LITTLE_ENDIAN)
                        .float
                    _temperature.value = temp
                    Log.i("BLE", "Temperature updated: $temp")
                } else {
                    Log.w("BLE", "Invalid characteristic value")
                    _connectionState.value = BleConnectionState.Error("Invalid data received")
                }
            } else {
                Log.w("BLE", "Read failed, status = 0x${status.toString(16)}")
                _connectionState.value = BleConnectionState.Error("Failed to read temperature")
            }
        }
    }
}