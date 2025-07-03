import ble from '@ohos.bluetooth.ble';
import access from '@ohos.bluetooth.access';
import connection from '@ohos.bluetooth.connection';
import constant from '@ohos.bluetooth.constant';
import { BusinessError } from '@ohos.base';
import hilog from '@ohos.hilog';

// Constants for logging
const DOMAIN = 0xF001;
const TAG = 'BleManager';

/** Connection state for BLE device */
export enum BleConnectionState {
  Disconnected,
  Scanning,
  Connecting,
  Connected,
  Error
}

/* Service and characteristic UUIDs for the BLE device */
const SERVICE_UUID = '12345678-1234-1000-8000-00805F9B34FB';
const TEMP_CHAR_UUID = '87654321-1234-1000-8000-00805F9B34FB';

/**
 * Manages BLE device connections and temperature readings
 * Handles scanning, connection, and data reception from BLE devices
 */
export default class BleManager {
  /* ---------- Observable data ---------- */
  public temperature: number | null = null;
  public connectionState: BleConnectionState = BleConnectionState.Disconnected;

  /* ---------- External callbacks ---------- */
  private onTempReadCb?: (t: number | null) => void;
  private onConnChangeCb?: (s: BleConnectionState) => void;

  /* ---------- Private fields ---------- */
  private gatt?: ble.GattClientDevice;
  private readonly SCAN_TIMEOUT = 30_000;        // Timeout in milliseconds
  private scanTimeoutId: number = -1;

  /**
   * Registers a callback to be invoked when temperature value changes
   * @param cb - Callback function that receives the new temperature value or null
   */
  public setOnTemperatureRead(cb?: (t: number | null) => void): void {
    hilog.info(DOMAIN, TAG, 'Setting temperature read callback');
    this.onTempReadCb = cb;
  }

  /**
   * Registers a callback to be invoked when connection state changes
   * @param cb - Callback function that receives the new connection state
   */
  public setOnConnectionChange(cb?: (s: BleConnectionState) => void): void {
    hilog.info(DOMAIN, TAG, 'Setting connection change callback');
    this.onConnChangeCb = cb;
  }

  /**
   * Initiates BLE scan and attempts to connect to the first device with matching SERVICE_UUID
   * Includes hardware filtering to only receive advertisements from devices with our service
   */
  public connect(): void {
    hilog.info(DOMAIN, TAG, 'Starting connection process');

    if (!this.ensureBluetoothOn()) {
      hilog.error(DOMAIN, TAG, 'Bluetooth is not enabled');
      return;
    }

    this.updateConnectionState(BleConnectionState.Scanning);
    hilog.info(DOMAIN, TAG, 'Starting BLE scan');

    // Hardware filter - only devices with specified UUID will be discovered
    ble.on('BLEDeviceFind', this.onDeviceFound);

    ble.startBLEScan([{ serviceUuid: SERVICE_UUID  }], { //serviceUuid: SERVICE_UUID
      dutyMode: ble.ScanDuty.SCAN_MODE_LOW_LATENCY
    });

    // Set timeout for scan operation
    this.scanTimeoutId = setTimeout(() => {
      hilog.warn(DOMAIN, TAG, 'Scan timeout reached');
      if (this.connectionState === BleConnectionState.Scanning) {
        this.stopScan();
        this.updateConnectionState(BleConnectionState.Error);
      }
    }, this.SCAN_TIMEOUT);
  }

  /**
   * Disconnects from the current device, closes GATT, and cleans up resources
   */
  public disconnect(): void {
    hilog.info(DOMAIN, TAG, 'Disconnecting from device');
    this.stopScan();

    try {
      if (this.gatt) {
        hilog.debug(DOMAIN, TAG, 'Closing GATT connection');
        this.gatt.disconnect();
        this.gatt.close();
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Error during disconnect: ${error}`);
    }

    this.gatt = undefined;
    this.updateTemperature(null);
    this.updateConnectionState(BleConnectionState.Disconnected);
  }

  /**
   * Verifies if Bluetooth is enabled
   * @returns boolean indicating if Bluetooth is enabled
   */
  private ensureBluetoothOn(): boolean {

    const state = access.getState();

    hilog.debug(DOMAIN, TAG, `Checking Bluetooth state -> ${state}`);

    if (state !== access.BluetoothState.STATE_ON) {
      hilog.error(DOMAIN, TAG, 'Bluetooth is not enabled');
      this.updateConnectionState(BleConnectionState.Error);
      return false;
    }
    return true;
  }

  /**
   * Callback triggered when a BLE device is found during scanning
   * @param results - Array of scan results containing found devices
   */
  private onDeviceFound = (results: Array<ble.ScanResult>): void => {
    hilog.info(DOMAIN, TAG, `Found ${results.length} devices`);
    if (!results.length) return;

    const deviceId = results[0].deviceId;
    hilog.info(DOMAIN, TAG, `Connecting to device: [${deviceId}] ${connection.getRemoteDeviceName(deviceId)}`);

    this.stopScan();
    this.updateConnectionState(BleConnectionState.Connecting);

    this.gatt = ble.createGattClientDevice(deviceId);
    this.gatt.on('BLEConnectionStateChange', this.onConnectionChange);

    try {
      hilog.debug(DOMAIN, TAG, 'Initiating GATT connection');
      this.gatt.connect();
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Connection error: ${error}`);
      this.updateConnectionState(BleConnectionState.Error);
    }
  };

  /**
   * Handles BLE connection state changes
   * @param ev - Connection state change event
   */
  private onConnectionChange = async (ev: ble.BLEConnectionChangeState) => {
    hilog.info(DOMAIN, TAG, `Connection state changed: ${ev.state}`);

    if (ev.state === constant.ProfileConnectionState.STATE_CONNECTED) {
      hilog.info(DOMAIN, TAG, 'Device connected, discovering services');
      this.updateConnectionState(BleConnectionState.Connected);

      try {
        const services = await this.gatt!.getServices();
        hilog.debug(DOMAIN, TAG, `Found ${services.length} services`);

        const tempChar = services
          .flatMap(s => s.characteristics)
          .find(c => c.characteristicUuid.toLowerCase() === TEMP_CHAR_UUID.toLowerCase());

        if (!tempChar) {
          throw new Error('Temperature characteristic not found');
        }

        // Initial temperature reading
        hilog.debug(DOMAIN, TAG, 'Reading initial temperature value');
        await this.readTemperature(tempChar);

        // Enable notifications
        //hilog.debug(DOMAIN, TAG, 'Enabling temperature notifications');
        //await this.gatt!.setCharacteristicChangeNotification(tempChar, true);
        //this.gatt!.on('BLECharacteristicChange', this.onCharacteristicChange);

      } catch (e) {
        hilog.error(DOMAIN, TAG, `GATT operation error: ${(e as BusinessError).message}`);
        this.updateConnectionState(BleConnectionState.Error);
      }
    } else if (ev.state === constant.ProfileConnectionState.STATE_DISCONNECTED) {
      hilog.info(DOMAIN, TAG, 'Device disconnected');
      this.disconnect();
    }
  };

  /**
   * Handles characteristic value changes (notifications)
   * @param ch - Changed characteristic
   */
  private onCharacteristicChange = (ch: ble.BLECharacteristic) => {
    if (ch.characteristicUuid.toLowerCase() !== TEMP_CHAR_UUID.toLowerCase()) return;
    hilog.debug(DOMAIN, TAG, 'Received temperature notification');
    this.updateTemperature(this.bytesToFloat(ch.characteristicValue));
  };

  /**
   * Reads temperature value from the characteristic
   * @param char - Temperature characteristic
   */
  private async readTemperature(char: ble.BLECharacteristic): Promise<void> {
    hilog.debug(DOMAIN, TAG, 'Reading temperature characteristic');
    const updated = await this.gatt!.readCharacteristicValue(char);
    const temp = this.bytesToFloat(updated.characteristicValue);
    hilog.info(DOMAIN, TAG, `Temperature read: ${temp}`);
    this.updateTemperature(temp);
  }

  /**
   * Updates temperature value and triggers callback
   * @param t - New temperature value
   */
  private updateTemperature(t: number | null): void {
    hilog.debug(DOMAIN, TAG, `Updating temperature to: ${t}`);
    this.temperature = t;
    this.onTempReadCb?.(t);
  }

  /**
   * Updates connection state and triggers callback
   * @param s - New connection state
   */
  private updateConnectionState(s: BleConnectionState): void {
    hilog.debug(DOMAIN, TAG, `Updating connection state to: ${BleConnectionState[s]}`);
    this.connectionState = s;
    this.onConnChangeCb?.(s);
  }

  /**
   * Converts byte array to float value
   * @param buf - ArrayBuffer containing float value
   * @returns Parsed float value
   */
  private bytesToFloat(buf: ArrayBuffer): number {
    const dv = new DataView(buf);
    return dv.getFloat32(0, true);  // little-endian
  }

  /**
   * Stops BLE scanning and cleans up scan resources
   */
  private stopScan(): void {
    hilog.debug(DOMAIN, TAG, 'Stopping BLE scan');
    clearTimeout(this.scanTimeoutId);
    ble.off('BLEDeviceFind', this.onDeviceFound);
    try {
      ble.stopBLEScan();
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Error stopping scan: ${error}`);
    }
  }
}
