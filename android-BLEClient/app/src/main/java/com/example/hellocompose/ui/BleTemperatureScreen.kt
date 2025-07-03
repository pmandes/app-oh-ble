package com.example.hellocompose.ui

import android.Manifest
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.annotation.RequiresApi
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.core.content.PermissionChecker.PERMISSION_GRANTED
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.hellocompose.ble.BleConnectionState
import com.example.hellocompose.viewmodel.BleViewModel

/**
 * Manages BLE permissions state using Compose state.
 * Automatically requests required permissions if not granted.
 *
 * Required permissions:
 * - BLUETOOTH_SCAN for discovering devices
 * - BLUETOOTH_CONNECT for connecting to devices
 * - ACCESS_FINE_LOCATION for scanning BLE devices (required on some Android versions)
 *
 * @return Boolean indicating if all required permissions are granted
 */
@RequiresApi(Build.VERSION_CODES.S)
@Composable
fun rememberBlePermissionState(): Boolean {
    // Get the current context
    val ctx = LocalContext.current
    // Required permissions for BLE operations
    val perms = arrayOf(
        Manifest.permission.BLUETOOTH_SCAN,
        Manifest.permission.BLUETOOTH_CONNECT,
        Manifest.permission.ACCESS_FINE_LOCATION,
    )
    // State to track if all permissions are granted
    var granted by remember { mutableStateOf(false) }

    // Permission request launcher
    val launcher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestMultiplePermissions()
    ) { res -> granted = res.values.all { it } }

    // Check permissions on first composition
    LaunchedEffect(Unit) {
        // If all permissions are already granted, set granted to true
        if (perms.all { ContextCompat.checkSelfPermission(ctx, it) == PERMISSION_GRANTED }) {
            granted = true
        } else {
            // Otherwise, launch the permission request dialog
            launcher.launch(perms)
        }
    }
    // Return whether all permissions are granted
    return granted
}

/**
 * Main screen composable for BLE temperature sensor.
 * Shows:
 * - Connection status and controls
 * - Current temperature reading
 * - Error messages when applicable
 *
 * Features:
 * - Automatic permission handling
 * - Connect/Disconnect buttons
 * - Loading indicators during BLE operations
 * - Error display with user-friendly messages
 *
 * @param vm BleViewModel instance for managing BLE operations
 */
@RequiresApi(Build.VERSION_CODES.S)
@Composable
fun BleTemperatureScreen(vm: BleViewModel = viewModel()) {
    val permitted = rememberBlePermissionState()
    val temp by vm.temperature.collectAsState()
    val connectionState by vm.connectionState.collectAsState()

    // Main container
    Column(
        modifier = Modifier.fillMaxSize().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        // Title
        Text("TempService demo", style = MaterialTheme.typography.titleLarge)
        Spacer(Modifier.height(32.dp))

        // Connection state display
        when (connectionState) {
            is BleConnectionState.Error -> {
                // Show error message in red
                Text(
                    (connectionState as BleConnectionState.Error).message,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.error,
                    textAlign = TextAlign.Center
                )
            }
            BleConnectionState.Scanning -> {
                // Show scanning indicator
                CircularProgressIndicator()
                Spacer(Modifier.height(8.dp))
                Text("Scanning for devices...", style = MaterialTheme.typography.bodyMedium)
            }
            BleConnectionState.Connecting -> {
                // Show connecting indicator
                CircularProgressIndicator()
                Spacer(Modifier.height(8.dp))
                Text("Connecting...", style = MaterialTheme.typography.bodyMedium)
            }
            else -> { /* Other states don't need special UI */ }
        }

        Spacer(Modifier.height(16.dp))

        // Connection control buttons
        when (connectionState) {
            BleConnectionState.Connected -> {
                // Show disconnect button when connected
                OutlinedButton(
                    onClick = { vm.disconnect() }
                ) { Text("Disconnect") }
            }
            BleConnectionState.Scanning, BleConnectionState.Connecting -> {
                // Hide controls during operations
            }
            else -> {
                // Show connect button when ready
                Button(
                    onClick = { if (permitted) vm.connect() },
                    enabled = permitted && connectionState !is BleConnectionState.Error
                ) { Text("Connect") }
            }
        }

        Spacer(Modifier.height(24.dp))

        // Temperature display
        Text(
            temp?.let { "🌡️  %.2f °C".format(it) } ?: "no data",
            style = MaterialTheme.typography.headlineMedium
        )
    }
}
