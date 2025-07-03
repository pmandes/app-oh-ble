package com.example.hellocompose.viewmodel

import android.annotation.SuppressLint
import android.app.Application
import androidx.lifecycle.AndroidViewModel
import com.example.hellocompose.ble.BleConnectionState
import com.example.hellocompose.ble.BleManager
import kotlinx.coroutines.flow.StateFlow

/**
 * ViewModel for managing BLE temperature sensor functionality.
 * Acts as a bridge between the UI and BLE operations, delegating all BLE work to BleManager.
 *
 * Features:
 * - Exposes temperature readings as StateFlow
 * - Handles BLE connection state
 * - Manages BLE lifecycle with the ViewModel lifecycle
 * - Provides simple connect/disconnect API for the UI
 *
 * @param app Application context required for BLE operations
 */
class BleViewModel(app: Application) : AndroidViewModel(app) {
    // BLE operations manager
    private val bleManager = BleManager(app)

    /**
     * Current temperature reading from the BLE sensor.
     * Updates automatically when new readings are available.
     * Null when no data is available (e.g., disconnected).
     */
    val temperature: StateFlow<Float?> = bleManager.temperature

    /**
     * Current state of the BLE connection.
     * Updates automatically as connection state changes.
     * Used by the UI to show appropriate status and controls.
     */
    val connectionState: StateFlow<BleConnectionState> = bleManager.connectionState

    /**
     * Initiates BLE connection process.
     * Will start scanning for compatible devices and connect to the first one found.
     * Requires Bluetooth permissions to be granted before calling.
     */
    @SuppressLint("MissingPermission")
    fun connect() = bleManager.connect()

    /**
     * Disconnects from the currently connected BLE device.
     * Safe to call even when not connected.
     * Will clear any existing connection, stop scans, and clean up resources.
     */
    fun disconnect() = bleManager.disconnect()

    /**
     * Called when ViewModel is being destroyed.
     * Ensures proper cleanup of BLE resources by disconnecting.
     */
    override fun onCleared() {
        super.onCleared()
        bleManager.disconnect()
    }
}
