package com.example.hellocompose.ble

/**
 * Represents the current state of BLE connection.
 * Used to track and display the connection status in the UI.
 */
sealed class BleConnectionState {
    /** No device connected */
    object Disconnected : BleConnectionState()

    /** Currently scanning for BLE devices */
    object Scanning : BleConnectionState()

    /** Attempting to connect to a device */
    object Connecting : BleConnectionState()

    /** Successfully connected to a device */
    object Connected : BleConnectionState()

    /** An error occurred during BLE operations */
    data class Error(val message: String) : BleConnectionState()
}