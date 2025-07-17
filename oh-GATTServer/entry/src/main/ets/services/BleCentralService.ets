import ble from '@ohos.bluetooth.ble';
import connection from '@ohos.bluetooth.connection';
import access from '@ohos.bluetooth.access';
import { BusinessError } from '@ohos.base';

/**
 * Some scan result objects carry the device name under a `deviceName` property.
 * This helper interface allows us to safely cast and access that optional field.
 */
interface DeviceNameCarrier { deviceName?: string }

/**
 * Represents a single Bluetooth Low Energy (BLE) device as seen from the central
 * (client) role.
 */
export interface DeviceInfo {
  /** Hardware identifier passed to all BLE APIs */
  deviceId: string;
  /** Human‑readable name of the device (may be empty if not provided) */
  name: string;
  /** Last received RSSI during advertisement discovery (dBm) */
  rssi: number;
  /** `true` if the device is bonded (paired) with the host */
  isPaired: boolean;
  /** `true` when there is an active GATT connection */
  isConnected: boolean;
}

/**
 * High‑level wrapper that handles common BLE‑Central operations:
 *  • listing already‑paired devices,
 *  • scanning for peripherals (results are **always sorted by RSSI**),
 *  • tracking connection state,
 *  • initiating connections and disconnections.
 *
 * The class now includes **API 12‑compliant checks** to ensure the Bluetooth
 * adapter is powered on before any BLE call is made, preventing runtime
 * crashes when the user disables Bluetooth.
 */
export default class BleCentralService {

  /** Devices that are already bonded with the host (sorted by RSSI) */
  public pairedDevices: DeviceInfo[] = [];

  /** Devices that have been seen during the current scan session (sorted by RSSI) */
  public discoveredDevices: DeviceInfo[] = [];

  /** Fast lookup of {@link DeviceInfo} instances by their `deviceId` */
  private deviceMap: Map<string, DeviceInfo> = new Map();

  /** Optional callback that UI layers can subscribe to for real‑time scan updates */
  private scanCallback?: (devices: DeviceInfo[]) => void;

  /**
   * @returns `true` when the local Bluetooth adapter is powered on.
   * Uses the API‑12 Bluetooth Access module (`access.getState`). If the call
   * fails (e.g. permission not granted) the function returns `false` so that
   * BLE operations are skipped gracefully.
   */
  private isBtOn(): boolean {
    try {
      const state = access.getState();
      return state === access.BluetoothState.STATE_ON ||
        state === access.BluetoothState.STATE_BLE_ON; // treat LE‑only as ON
    } catch {
      return false;
    }
  }

  /** Helper that sorts a given {@link DeviceInfo} array in‑place by **descending** RSSI. */
  private sortBySignalStrength(arr: DeviceInfo[]): void {
    arr.sort((a, b) => b.rssi - a.rssi);
  }

  /**
   * Retrieves the list of bonded devices and updates their `isConnected` flag.
   * If Bluetooth is **OFF**, the method returns an empty array and skips all BLE
   * calls to avoid `BusinessError 2900003`.
   */
  public updatePairedDevices(): DeviceInfo[] {

    if (!this.isBtOn()) {
      console.warn('[BLE] updatePairedDevices skipped – Bluetooth is OFF');
      this.pairedDevices = [];
      return [];
    }

    let bondedIds: string[] = [];
    let connectedIds: string[] = [];
    try {
      bondedIds = connection.getPairedDevices();
      connectedIds = ble.getConnectedBLEDevices();
    } catch (e) {
      const err = e as BusinessError;
      if (err.code === 2900003) { // Bluetooth disabled during call
        console.warn('[BLE] Bluetooth turned OFF during updatePairedDevices');
        this.pairedDevices = [];
        return [];
      }
      console.error(`[BLE] unexpected error in updatePairedDevices: ${(e as BusinessError).code}/${(e as BusinessError).message}`);
      this.pairedDevices = [];
      return [];
    }

    const connectedSet = new Set<string>(connectedIds);

    this.pairedDevices = bondedIds.map(id => {
      let name = '';
      try {
        name = connection.getRemoteDeviceName(id) || '';
      } catch {}
      const info: DeviceInfo = {
        deviceId: id,
        name,
        rssi: 0,
        isPaired: true,
        isConnected: connectedSet.has(id),
      };
      this.deviceMap.set(id, info);
      return info;
    });

    this.sortBySignalStrength(this.pairedDevices);
    return this.pairedDevices;
  }

  /** Starts a BLE scan and feeds incremental results to `cb`. */
  public startScan(cb: (devices: DeviceInfo[]) => void): void {
    console.info('[BLE] startScan called');

    if (!this.isBtOn()) {
      console.warn('[BLE] startScan aborted – Bluetooth is OFF');
      cb([]); // deliver empty list so UI can show warning
      return;
    }

    this.updatePairedDevices();
    this.discoveredDevices = [];
    this.scanCallback = cb;

    ble.off('BLEDeviceFind', this.onDeviceFound);
    ble.on('BLEDeviceFind', this.onDeviceFound);

    const filters: ble.ScanFilter[] = [{}];

    try {
      ble.startBLEScan(filters);
    } catch (e) {
      const err = e as BusinessError;
      console.error(`[BLE] startBLEScan error: ${err.code} / ${err.message}`);
    }
  }

  /** Stops an ongoing BLE scan and removes the event listener. */
  public stopScan(): void {
    console.info('[BLE] stopScan called');
    ble.off('BLEDeviceFind', this.onDeviceFound);
    try {
      ble.stopBLEScan();
    } catch (e) {
      const err = e as BusinessError;
      console.error(`[BLE] stopBLEScan error: ${err.code} / ${err.message}`);
    }
    this.scanCallback = undefined;
  }

  /** Internal handler for **BLEDeviceFind** platform events. */
  private onDeviceFound = (results: ble.ScanResult[]): void => {

    let needsRefresh = false;

    results.forEach(r => {

      console.info(`[BLE] onDeviceFound() ->  ${JSON.stringify(r) }`);

      if (r.deviceName === '') return; // ignore nameless packets

      const id = r.deviceId;
      const existing = this.deviceMap.get(id);

      if (existing) {

        // Update only if RSSI changed “enough” (≥ 3 dB)

        const delta = Math.abs(existing.rssi - r.rssi);

        if (delta >= 3) {
          existing.rssi = r.rssi;
          needsRefresh = true;     // flag that the list really changed
        }

      } else {

        const info: DeviceInfo = {
          deviceId: id,
          name: (r as DeviceNameCarrier).deviceName ?? '',
          rssi: r.rssi,
          isPaired: false,
          isConnected: false,
        };

        this.deviceMap.set(id, info);
        this.discoveredDevices.push(info);

        needsRefresh = true;
      }
    });

    this.sortBySignalStrength(this.discoveredDevices);

    if (needsRefresh) {
      this.sortBySignalStrength(this.discoveredDevices);
      this.scanCallback?.(this.discoveredDevices.slice());
    }
  };

  /** Initiates a GATT connection to a peripheral. */
  public async connect(deviceId: string): Promise<ble.GattClientDevice | null> {

    if (!this.isBtOn()) {
      console.warn('[BLE] connect ignored – Bluetooth is OFF');
      return null;
    }

    console.info(`[BLE] connect -> ${deviceId}`);

    try {
      const client = ble.createGattClientDevice(deviceId);
      await client.connect();

      const services = await client.getServices()

      console.info(`[BLE] connect client -> ${JSON.stringify(services)}`);

      const info = this.deviceMap.get(deviceId);

      if (info) info.isConnected = true;

      console.info(`[BLE] connect info -> ${JSON.stringify(info)}`);

      return client;

    } catch (e) {
      const err = e as BusinessError;
      console.error(`[BLE] connect error: ${err.code}/${err.message}`);

      return null;
    }
  }

  /** Marks the cached device as disconnected (UI only). */
  public disconnect(deviceId: string): void {
    const info = this.deviceMap.get(deviceId);
    if (info && info.isConnected) {

      console.info(`[BLE] disconnect -> ${deviceId}`);

      try {
        ble.createGattClientDevice(deviceId).disconnect?.(); // or .close() depending on SDK
      } catch (e) {
        const err = e as BusinessError;
        console.error(`[BLE] disconnect error: ${err.code}/${err.message}`);
      }
      info.isConnected = false;
    }
  }
}
