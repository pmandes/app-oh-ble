import BleCentralService, { DeviceInfo } from '../services/BleCentralService';
import access from '@ohos.bluetooth.access';
import { BusinessError } from '@ohos.base';
import { AppHeader } from './components/AppHeader';
import { DeviceItem } from './components/DeviceItem';
//import BleViewModel from './viewmodel/BleViewModel'

/**
 * IndexPage – main UI for browsing, scanning and connecting BLE peripherals.
 * ---------------------------------------------------------------------------
 * • Shows two lists: paired devices & devices discovered during current scan.
 * • Lets the user connect/disconnect and fetch temperature from peripherals.
 * • Reacts to Bluetooth‑adapter state; gracefully degrades when BT is OFF.
 */
@Entry
@Component
struct IndexPage {

  //@Provide private viewModel: BleViewModel = new BleViewModel();

  // ──────────────────────────────── State ──────────────────────────────────

  /** Service handling low‑level BLE operations (scan/connect/disconnect) */
  @State private bleService: BleCentralService = new BleCentralService();

  /** Currently bonded (paired) peripherals */
  @State private pairedDevices: DeviceInfo[] = [];

  /** Peripherals found in the active scan session */
  @State private discoveredDevices: DeviceInfo[] = [];

  /** Flag – true while a scan is running */
  @State private scanning: boolean = false;

  /** Flag – true when adapter is ON or BLE‑only */
  @State private btEnabled: boolean = true;

  /** Latest temperature readings keyed by deviceId */
  @State private deviceTemperatures: Map<string, number> = new Map();

  /** DeviceIds currently being queried for temperature (used to lock button) */
  @State private queryingIds: Set<string> = new Set();

  /** Listener reference so it can be detached in onPageHide() */
  private btStateListener?: (state: number) => void;

  // ────────────────────────── Life‑cycle hooks ─────────────────────────────

  aboutToAppear(): void {

    console.debug("Index page: aboutToAppear().");
  }

  /** Runs each time the page becomes visible. */
  onPageShow(): void {

    console.debug("Index page: onPageShow().");

    this.btEnabled = this.isBlueToothOn();

    // Subscribe to adapter‑state changes
    this.btStateListener = (state: number) => {

      this.btEnabled = state === access.BluetoothState.STATE_ON ||
        state === access.BluetoothState.STATE_BLE_ON;

      if (!this.btEnabled) {
        // Adapter switched OFF → stop scan & clear UI
        if (this.scanning) {
          this.bleService.stopScan();
          this.scanning = false;
        }
        this.pairedDevices = [];
        this.discoveredDevices = [];
      } else {
        // Adapter switched ON → refresh & restart scan
        this.refreshListsAndMaybeScan();
      }
    };

    access.on?.('stateChange', this.btStateListener);

    //this.refreshListsAndMaybeScan();
  }

  /** Runs when the page goes off‑screen. */
  onPageHide(): void {

    console.debug("Index page: onPageHide().");

    // 1️⃣ Stop scan if still running (prevents background BLE load)
    if (this.scanning) {
      this.bleService.stopScan();
      this.scanning = false;
    }

    // 2️⃣ Detach BT‑state listener
    if (this.btStateListener) {
      access.off?.('stateChange', this.btStateListener);
      this.btStateListener = undefined;
    }
  }

  // ─────────────────────────── Helpers / Logic ─────────────────────────────

  /** Safe check of current adapter state. */
  private isBlueToothOn(): boolean {
    try {
      const st = access.getState();
      return st === access.BluetoothState.STATE_ON || st === access.BluetoothState.STATE_BLE_ON;
    } catch (e) {
      const err = e as BusinessError;
      console.error(`[UI] getState error ${err.code}/${err.message}`);
      return false;
    }
  }

  /** Re‑fetches paired list and (re)starts active scan. */
  private refreshListsAndMaybeScan(): void {
    if (!this.btEnabled) return;

    console.debug(`refreshListsAndMaybeScan()`);

    this.pairedDevices = this.bleService.updatePairedDevices().slice();

    this.bleService.startScan((devices: DeviceInfo[]) => {
      this.discoveredDevices = devices.slice();
    });
    this.scanning = true;
  }

  /** Toggles scan ON ↔ OFF. */
  private toggleScan(): void {
    if (!this.btEnabled) return;

    console.debug(`refreshListsAndMaybeScan()`);

    if (this.scanning) {
      this.bleService.stopScan();
      this.scanning = false;
    } else {
      this.refreshListsAndMaybeScan();
    }
  }

  /** Connects or disconnects from a peripheral, then refreshes paired list. */
  private toggleConnect(dev: DeviceInfo): void {
    if (!this.btEnabled) return;

    console.debug(`toggleConnect -> ${dev.name} isConnected:${dev.isConnected}`);

    if (dev.isConnected) {
      this.bleService.disconnect(dev.deviceId);
      dev.isConnected = false;
    } else {
      this.bleService.connect(dev.deviceId);
      dev.isConnected = true;
    }

    this.pairedDevices = this.bleService.updatePairedDevices();
  }

  /** Root layout: header + two device sections. */
  build(): void {
    Column({ space: 12 }) {

      AppHeader({
        isScanning: this.scanning,
        btEnabled: this.btEnabled,
        onScanBtnClick: () => this.toggleScan()
      });

      this.pairedSection();

      this.discoveredSection();

    }.padding({ top: 16, left: 16, right: 16 });
  }

  // ───────────────────────────── UI builders ───────────────────────────────

  /** List of paired devices with Connect/Temp actions. */
  @Builder private pairedSection(): void {

    Text('Paired Devices')
      .fontSize(16).fontWeight(FontWeight.Medium)
      .margin({ bottom: 8 });

    List({ space: 8 }) {

      ForEach(this.pairedDevices, (dev: DeviceInfo) => {

        ListItem() {

          DeviceItem({
            device: dev,
            btEnabled: this.btEnabled,
            showRssi: true,
            onConnectClick: () => this.toggleConnect(dev),
            onQueryTemperatureClick: () => {}
          })

        }
      }, (d: DeviceInfo) => d.deviceId);
    }
  }

  /** List of peripherals discovered during current scan. */
  @Builder private discoveredSection(): void {

    Text('Discovered Devices')
      .fontSize(16).fontWeight(FontWeight.Medium)
      .margin({ bottom: 8 });

    if (this.discoveredDevices.length > 0) {

      List({ space: 8 }) {

        ForEach(this.discoveredDevices, (dev: DeviceInfo) => {

          ListItem() {

            DeviceItem({
              device: dev,
              btEnabled: this.btEnabled,
              showRssi: true,
              onConnectClick: () => this.toggleConnect(dev),
              onQueryTemperatureClick: () => {}
            })

          }
        }, (d: DeviceInfo) => d.deviceId);
      }
    } else {
      Text(
        !this.btEnabled
          ? 'Bluetooth is OFF'
          : (this.scanning ? 'Scanning...' : 'No devices found')
      )
        .fontSize(14).opacity(0.6)
        .margin({ bottom: 8 });
    }
  }

}
