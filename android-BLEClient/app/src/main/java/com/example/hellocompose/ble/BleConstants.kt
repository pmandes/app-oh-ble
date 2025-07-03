package com.example.hellocompose.ble

import java.util.UUID

/**
 * UUID of the BLE service that provides temperature measurements.
 * This should match the UUID configured on the BLE peripheral device.
 */
val SERVICE_UUID = UUID.fromString("12345678-1234-1000-8000-00805F9B34FB")

/**
 * UUID of the characteristic that contains the temperature value.
 * This should match the UUID configured on the BLE peripheral device.
 */
val TEMP_CHAR_UUID = UUID.fromString("87654321-1234-1000-8000-00805F9B34FB")