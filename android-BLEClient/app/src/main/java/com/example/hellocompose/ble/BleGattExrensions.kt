package com.example.hellocompose.ble

import android.bluetooth.BluetoothGattCharacteristic

/**
 * Extension function for BluetoothGattCharacteristic that returns a debug string.
 * Useful for logging and debugging BLE operations.
 *
 * @return A string containing:
 * - UUID of the characteristic
 * - Properties flags (in hex)
 * - Permissions (in hex)
 * - Value length
 * - Raw value (in hex)
 */
fun BluetoothGattCharacteristic.debugString(): String {
    val hex = value?.joinToString(" ") { "%02X".format(it) } ?: "null"
    return "uuid=$uuid  props=0x${properties.toString(16)}  perms=0x${permissions.toString(16)}  len=${value?.size ?: 0}  value=[$hex]"
}
