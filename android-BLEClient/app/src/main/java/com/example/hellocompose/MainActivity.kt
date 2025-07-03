package com.example.hellocompose

import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.annotation.RequiresApi
import androidx.compose.material3.MaterialTheme
import com.example.hellocompose.ui.BleTemperatureScreen

/**
 * Main activity for the BLE temperature sensor application.
 * Handles UI setup and permission management.
 */
class MainActivity : ComponentActivity() {
    /**
     * Called when the activity is starting. Sets up the Compose content.
     * @param savedInstanceState If the activity is being re-initialized after previously being shut down then this Bundle contains the data it most recently supplied.
     */
    @RequiresApi(Build.VERSION_CODES.S)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            MaterialTheme {
                BleTemperatureScreen()
            }
        }
    }
}
