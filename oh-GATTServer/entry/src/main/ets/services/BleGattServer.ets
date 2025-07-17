import { hilog } from '@kit.PerformanceAnalysisKit';
import ble from '@ohos.bluetooth.ble';
import access from '@ohos.bluetooth.access';
import { BusinessError } from '@ohos.base';

/**
 * BLE GATT server wrapper exposing a simple **Temperature Service** that can be
 * discovered and connected to by any BLE‑capable central (e.g. smartphone).
 *
 * ### GATT hierarchy
 * ```
 * Service (0x12345678‑...)
 * ├── Temperature Characteristic (0x87654321‑...)  [READ | NOTIFY]
 * │   └── Client‑Characteristic‑Configuration Descriptor (0x2902)
 * └── Unit Characteristic (0x87654322‑...)         [READ | WRITE]
 * ```
 *
 * > All UUIDs are randomly generated, 128‑bit and fall within the Bluetooth
 * > SIG “service + characteristic” UUID pattern (see Core Spec Vol 3, Part G §3.2).
 *
 * @packageDocumentation
 */
export default class BleGattServer {
  /* ──────────────── CONSTANTS ──────────────── */

  /** Domain code used by `hilog` for all log lines originating in this class. */
  private static readonly LOG_DOMAIN = 0x0000;

  /** 128‑bit UUID of the primary *Temperature Service*. */
  private static readonly SERVICE_UUID = '12345678-1234-1000-8000-00805F9B34FB';

  /** UUID of the *Temperature* characteristic (float32/int32, little‑endian). */
  private static readonly TEMP_CHAR_UUID = '87654321-1234-1000-8000-00805F9B34FB';

  /** UUID of the *Unit* characteristic (uint8 code: 0 = °C, 1 = °F, …). */
  private static readonly UNIT_CHAR_UUID = '87654322-1234-1000-8000-00805F9B34FB';

  /** UUID of the Client‑Characteristic‑Configuration Descriptor (CCCD). */
  private static readonly CCCD_UUID = '00002902-0000-1000-8000-00805F9B34FB';

  /* ──────────────── STATE ──────────────── */

  /** `true` while advertising is active, prevents duplicated starts/stops. */
  private advertisingOn = false;

  /** Handle returned by `ble.createGattServer()`; `undefined` until created. */
  private gattServer: ble.GattServer | undefined;

  /* ──────────────── PUBLIC API ──────────────── */

  /**
   * Builds the GATT hierarchy and registers it with the local BLE stack.
   *
   * @remarks
   * - Must be invoked *once* during application start‑up, before
   *   {@link startAdvertising}.
   * - Safe to call multiple times: subsequent calls overwrite the previous
   *   service.
   */
  public async prepareGattServer(): Promise<void> {
    hilog.debug(BleGattServer.LOG_DOMAIN, 'BleGattServer', 'Initializing GATT server…');

    const state = access.getState();
    const ids = [];//access.getPersistentDeviceIds();
    hilog.info(BleGattServer.LOG_DOMAIN, 'BleGattServer', `BT state: ${state}, IDs: ${ids}`);

    /* 1️⃣  Obtain a new GATT server instance */
    this.gattServer = ble.createGattServer();
    hilog.info(BleGattServer.LOG_DOMAIN, 'BleGattServer', 'GattServer instance created');

    this.addListeners(this.gattServer);

    const devices = ble.getConnectedBLEDevices();
    hilog.info(BleGattServer.LOG_DOMAIN, 'BleGattServer', `Conneted BLE devices: ${JSON.stringify(devices)}`);

    /* 2️⃣  Allocate CCCD (Client‑Characteristic‑Configuration Descriptor) buffer.
            Per spec, default value is 0x0000 = notifications & indications OFF. */
    const cccdBuffer = new ArrayBuffer(2);
    new Uint8Array(cccdBuffer).fill(0x00);

    const cccDescriptor: ble.BLEDescriptor = {
      serviceUuid: BleGattServer.SERVICE_UUID,
      characteristicUuid: BleGattServer.TEMP_CHAR_UUID,
      descriptorUuid: BleGattServer.CCCD_UUID,
      descriptorValue: cccdBuffer,
    };

    hilog.info(BleGattServer.LOG_DOMAIN, 'BleGattServer', `BLEDescriptor:  ${JSON.stringify(cccDescriptor)}`);

    /* 3️⃣  Assemble Temperature characteristic (readable, notifiable) */
    const tempValueBuffer = new ArrayBuffer(4); // placeholder for 32‑bit temperature
    const tempCharacteristic: ble.BLECharacteristic = {
      serviceUuid: BleGattServer.SERVICE_UUID,
      characteristicUuid: BleGattServer.TEMP_CHAR_UUID,
      properties: { read: true, notify: true },
      characteristicValue: tempValueBuffer,
      descriptors: [cccDescriptor],
    };

    hilog.info(BleGattServer.LOG_DOMAIN, 'BleGattServer', `BLECharacteristic:  ${JSON.stringify(tempCharacteristic)}`);

    /* 4️⃣  Assemble Unit characteristic (read/write).
            A single byte encodes the temperature unit (0‑255 reserved range). */
    const unitValueBuffer = new ArrayBuffer(1);
    const unitCharacteristic: ble.BLECharacteristic = {
      serviceUuid: BleGattServer.SERVICE_UUID,
      characteristicUuid: BleGattServer.UNIT_CHAR_UUID,
      properties: { read: true, write: true },
      characteristicValue: unitValueBuffer,
      descriptors: [],
    };

    hilog.info(BleGattServer.LOG_DOMAIN, 'BleGattServer', `BLECharacteristic:  ${JSON.stringify(unitCharacteristic)}`);

    /* 5️⃣  Finally, create the primary Service containing both characteristics. */
    const gattService: ble.GattService = {
      serviceUuid: BleGattServer.SERVICE_UUID,
      isPrimary: true,
      characteristics: [tempCharacteristic, unitCharacteristic],
      includeServices: [],
    };

    hilog.info(BleGattServer.LOG_DOMAIN, 'BleGattServer', `GattService:  ${JSON.stringify(gattService)}`);

    /* 6️⃣  Register the Service with the GATT server. */
    try {
      await this.gattServer.addService(gattService);

      hilog.info(
        BleGattServer.LOG_DOMAIN,
        'BleGattServer',
        `GattService registered: ${gattService.serviceUuid}`,
      );

    } catch (err) {
      const e = err as BusinessError | Error;
      hilog.error(
        BleGattServer.LOG_DOMAIN,
        'BleGattServer',
        `addService failed (code=${(e as BusinessError).code ?? 'n/a'}): ${e.message}`,
      );

    }

    hilog.info(BleGattServer.LOG_DOMAIN, 'BleGattServer', 'DONE');
  }

  /**
   * Starts connectable BLE advertising with a **scan‑response** carrying the
   * device name.
   *
   * @remarks
   * - Advertising is restarted automatically if already active.
   * - Uses a conservative TX power (−7 dBm) and 100 ms interval (160 slots).
   */
  public async startAdvertising(): Promise<void> {
    /* Prevent duplicate start: stop first if already running. */
    if (this.advertisingOn) {
      hilog.warn(
        BleGattServer.LOG_DOMAIN,
        'BleGattServer',
        'Advertising already running ‑ restarting…',
      );
      ble.stopAdvertising();
      this.advertisingOn = false;
    }

    /* Advertise Settings (connectable, medium TX power). */
    const setting: ble.AdvertiseSetting = {
      interval: 160, // 160 × 0.625 ms  = 100 ms
      txPower: -7,   // OpenHarmony maps −7 dBm ≈ “medium”
      connectable: true,
    };

    /* Manufacturer‑specific data (optional, example payload). */
    const manufacturerData: ble.ManufactureData = {
      manufactureId: 0x1234,                                  // arbitrary 16‑bit ID
      manufactureValue: new Uint8Array([1, 2, 3, 4]).buffer,  // 4‑byte opaque blob
    };

    /* Primary Advertising data: expose the Service UUID so centrals can
       filter for it.* */
    const advData: ble.AdvertiseData = {
      serviceUuids: [BleGattServer.SERVICE_UUID],
      manufactureData: [manufacturerData],
      serviceData: [],
      includeDeviceName: false, // name will go into scan‑response
    };

    /* Scan‑response: omit everything except the device name for brevity. */
    const advResp: ble.AdvertiseData = {
      serviceUuids: [],
      manufactureData: [],
      serviceData: [],
      includeDeviceName: true,
    };

    /* Start advertising. */
    try {
      await ble.startAdvertising(setting, advData, advResp);
      this.advertisingOn = true;
      hilog.info(BleGattServer.LOG_DOMAIN, 'BleGattServer', 'Advertising started successfully');
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(
        BleGattServer.LOG_DOMAIN,
        'BleGattServer',
        `startAdvertising failed (code=${e.code}): ${e.message}`,
      );
    }
  }

  /**
   * Stops BLE advertising if currently active.
   *
   * @returns `void`
   */
  public stopAdvertising(): void {
    if (!this.advertisingOn) {
      hilog.debug(BleGattServer.LOG_DOMAIN, 'BleGattServer', 'Advertising already stopped');
      return;
    }

    try {
      ble.stopAdvertising();
      this.advertisingOn = false;
      hilog.info(BleGattServer.LOG_DOMAIN, 'BleGattServer', 'Advertising stopped');
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(
        BleGattServer.LOG_DOMAIN,
        'BleGattServer',
        `stopAdvertising failed (code=${e.code}): ${e.message}`,
      );
    }
  }

  private addListeners(gattServer: ble.GattServer) {

    gattServer.on('characteristicRead', (req: ble.CharacteristicReadRequest) => {

      hilog.info(BleGattServer.LOG_DOMAIN, 'BleGattServer', `characteristicRead: ${JSON.stringify(req)}`);

      const buf = new ArrayBuffer(4);
      new DataView(buf).setFloat32(0, 23.8, true);

      this.gattServer!.sendResponse({
        deviceId: req.deviceId,
        transId:  req.transId,
        offset:   req.offset,
        status:   0,     // 0 == GATT_SUCCESS
        value:    buf,
      });

    });

    gattServer.on('characteristicWrite', (req) => {
      hilog.info(BleGattServer.LOG_DOMAIN, 'BleGattServer', `characteristicWrite: ${JSON.stringify(req)}`);
    });
    gattServer.on('descriptorRead', (req) => {
      hilog.info(BleGattServer.LOG_DOMAIN, 'BleGattServer', `descriptorRead: ${JSON.stringify(req)}`);
    });
    gattServer.on('descriptorWrite', (req) => {
      hilog.info(BleGattServer.LOG_DOMAIN, 'BleGattServer', `descriptorWrite: ${JSON.stringify(req)}`);
    });
    gattServer.on('connectionStateChange', (state) => {
      hilog.info(BleGattServer.LOG_DOMAIN, 'BleGattServer', `connectionStateChange: ${JSON.stringify(state)}`);
    });
    gattServer.on('BLEMtuChange', (num) => {
      hilog.info(BleGattServer.LOG_DOMAIN, 'BleGattServer', `BLEMtuChange: ${JSON.stringify(num)}`);
    });
  }

}

