# 5. Implementing a BLE GATT Client in OpenHarmony

Bluetooth Low Energy (BLE) lets a mobile device act as a **central GATT client**, connecting to peripheral GATT servers (e.g., sensors). In this tutorial, we will build an ArkTS app running on OpenHarmony (API ≥ 12) that scans for a BLE device exposing a **"Temperature Service"**, connects to it, and reads the temperature value from a GATT characteristic. We assume you know the **service and characteristic UUIDs** exposed by the BLE server, the client filters devices by this UUID and then uses GATT to read data. The app uses **ArkUI with ArkTS** (declarative UI in TypeScript) to provide a user interface for connecting and displaying the current temperature.

> **Note:** You need another BLE device acting as a GATT server with the appropriate service (e.g., an OpenHarmony device running the tutorial **Temperature Service** from the previous part). Our BLE client, as a **central**, will connect to it.

---

## 5.1 Required Bluetooth and Location permissions

Before scanning and connecting over BLE, the app must obtain the necessary permissions from the user. The permissions setting is identical to that for the GATT server implementation:

```ts
const PERMS: Permissions[] = [
  'ohos.permission.USE_BLUETOOTH',
  'ohos.permission.DISCOVER_BLUETOOTH',
  'ohos.permission.ACCESS_BLUETOOTH',
  'ohos.permission.APPROXIMATELY_LOCATION',
  'ohos.permission.LOCATION'
];

const permissionManager = new PermissionManager();
permissionManager.requestPermissions(this.context, PERMS, () => {
  // All permissions granted:
  windowStage.loadContent('pages/Index', (err) => {

    // Load content ot error handling...

  });
});
```

This ensures that before starting BLE scanning the app has Bluetooth and Location access. If the user denies any required permission, handle it appropriately (e.g., show a message and exit the BLE flow since operations won't work).

---

## 5.2 Initialize the BLE client and start scanning

After permissions, initialize the Bluetooth Low Energy module and **scan for a device exposing the target GATT service**. This logic lives in the `BleManager` class (file **BleManager.ts**). It manages BLE connection state, performs scanning, connects to a selected device, and reads data.

At the top, `BleManager` defines **service and characteristic UUIDs** used in the example:

```ts
const SERVICE_UUID = '12345678-1234-1000-8000-00805F9B34FB';
const TEMP_CHAR_UUID = '87654321-1234-1000-8000-00805F9B34FB';
```

We assume the target peripheral advertises the `SERVICE_UUID` (e.g., the Temperature Service server uses these identifiers). This allows filtering scan results by that identifier, **looking only for devices offering our service**.

The `connect()` method on `BleManager` starts the process of connecting to a BLE device. It first checks whether Bluetooth is turned on using `@ohos.bluetooth.access`:

```ts
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
```

Then `connect()` sets the state to **Scanning** and starts BLE scanning:

```ts
this.updateConnectionState(BleConnectionState.Scanning);
hilog.info(DOMAIN, TAG, 'Starting BLE scan');

// We set up a hardware filter – only devices containing our SERVICE_UUID
ble.on('BLEDeviceFind', this.onDeviceFound);
ble.startBLEScan([{ serviceUuid: SERVICE_UUID }], {
  dutyMode: ble.ScanDuty.SCAN_MODE_LOW_LATENCY
});
```

Additionally, `BleManager.connect()` sets a **timeout** in case no device is found within a given time (e.g., 30 seconds):

```ts
this.scanTimeoutId = setTimeout(() => {
  hilog.warn(DOMAIN, TAG, 'Scan timeout reached');
  if (this.connectionState === BleConnectionState.Scanning) {
    this.stopScan();
    this.updateConnectionState(BleConnectionState.Error);
  }
}, this.SCAN_TIMEOUT);
```

---

## 5.3 Detect a device and establish a GATT connection

Whenever the scanner finds a device that matches the criterion (has the `SERVICE_UUID`), our `onDeviceFound` callback is invoked with `Array<ble.ScanResult>`. In our implementation, we take the **first found device**, assuming it is our target sensor. Snippet of `onDeviceFound` in `BleManager`:

```ts
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
```

---

## 5.4 Discover GATT services and read the temperature characteristic

`onConnectionChange` in `BleManager` is called with a `ble.BLEConnectionChangeState` object. We read `state` and compare it against `@ohos.bluetooth.constant.ProfileConnectionState` constants. We handle two key cases: **CONNECTED** and **DISCONNECTED**. The handler looks like this:

```ts
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


    } catch (e) {
      hilog.error(DOMAIN, TAG, `GATT operation error: ${(e as BusinessError).message}`);
      this.updateConnectionState(BleConnectionState.Error);
    }
  } else if (ev.state === constant.ProfileConnectionState.STATE_DISCONNECTED) {
    hilog.info(DOMAIN, TAG, 'Device disconnected');
    this.disconnect();
  }
};
```

Our `disconnect()` cancels any ongoing scan, closes the GATT connection, and clears state so the UI reflects we're disconnected:

```ts
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
```

### Reading a characteristic value

Now let's look at `readTemperature(char)` called after connecting. It reads the remote temperature characteristic value, converts it to a number, and updates our state:

```ts
private async readTemperature(char: ble.BLECharacteristic): Promise<void> {
  hilog.debug(DOMAIN, TAG, 'Reading temperature characteristic');
  const updated = await this.gatt!.readCharacteristicValue(char);
  const temp = this.bytesToFloat(updated.characteristicValue);
  hilog.info(DOMAIN, TAG, `Temperature read: ${temp}`);
  this.updateTemperature(temp);
}
```

Helper `bytesToFloat` handles the conversion:

```ts
private bytesToFloat(buf: ArrayBuffer): number {
  const dv = new DataView(buf);
  return dv.getFloat32(0, true);  // little-endian
}
```

---

## 5.5 UI integration

The OpenHarmony app uses the **declarative ArkUI** written in ArkTS for user interaction. In our example, all UI logic is in **Index.ets**, which defines the main page component. The component is defined with the `@Component` decorator on `struct Index`. The `@Entry` decorator marks it as the **UI entry**, loaded first (as arranged in `EntryAbility`). Inside, we use `@State` variables to hold dynamic app state (e.g., temperature, connection status). **Changing such variables triggers automatic UI re‑render** thanks to ArkUI mechanisms. Here is a fragment of the component definition:

```ts
@Entry
@Component
struct Index {
  /** BLE manager instance for handling Bluetooth operations */
  private bleManager: BleManager = new BleManager();

  /** Current temperature value read from the BLE device */
  @State temperature: number | null = null;

  /** Flag: whether the device is currently connected */
  @State connected: boolean = false;

  /** Current connection status (text)) */
  @State status: string = "";
  ...
}
```

### Reacting to BLE state changes

A key place is the **lifecycle method** `aboutToAppear()` of `Index`. It's called just before the component appears, good time to subscribe to events and initialize data. We use it to register callbacks in `BleManager` so state changes and temperature reads update our @State variables:

```ts
aboutToAppear() {
  console.debug("[Index] aboutToAppear()");
  
  // Set temperature read callback
  this.bleManager.setOnTemperatureRead(temp => {
    console.debug(`[Index] setOnTemperatureRead -> ${temp}`);
    this.temperature = temp;
  });
  
  // Set connection status change callback
  this.bleManager.setOnConnectionChange(state => {
    console.debug(`[Index] setOnConnectionChange -> ${state}: ${BleConnectionState[state]}`);
    this.status = BleConnectionState[state];
    
    // Update connection flag and clear temp. after disconnecting
    if (state === BleConnectionState.Connected) {
      this.connected = true;
    } else {
      this.connected = false;
      this.temperature = null;
    }
  });
}
```

### Building the user interface

The component's `build()` method describes **how the UI should look**. It uses ArkUI primitives such as **Column**, **Text**, **Button** to declaratively build the view tree. Below is a simplified excerpt of `build()` with comments:

```ts
build() {
  RelativeContainer() {
    Column() {
      // App header
      Text('BLE Client')
        .fontSize($r('app.float.page_text_font_size'))
        .fontWeight(FontWeight.Bold)

      // Connect/Disconnect Button
      Button(this.connected ? 'Disconnect' : 'Connect')
        .onClick(() => this.onConnectButtonClick())
        .margin(16)

      // Displaying the temperature (with a thermometer emoticon)
      Text(
        this.temperature !== null
          ? `🌡️ ${this.temperature.toFixed(2)} °C`
          : 'no data'
      )
        .fontSize($r('app.float.page_text_font_size'))
        .fontWeight(FontWeight.Bold)

      // Connection status text
      Text(this.status)
        .fontSize($r('app.float.page_text_font_size'))
    }
    // Column alignment settings (centring on the screen)
    .alignRules({
      center: { anchor: '__container__', align: VerticalAlign.Center },
      middle: { anchor: '__container__', align: HorizontalAlign.Center }
    })
  }
  .height('100%')
  .width('100%')
}
```

The UI is simple and clear: a **Connect/Disconnect** button, the current temperature (or *no data*), and the textual **status**. ArkUI automatically refreshes the interface whenever observed `@State` variables change, so the button label, temperature text, and status update in real time.

---

## Summary

In this tutorial we implemented a full **BLE GATT client** flow in OpenHarmony using ArkTS and ArkUI. The app requests permissions (Bluetooth + Location), then uses `@ohos.bluetooth.ble` to scan devices (filtered by service UUID), connects as a GATT Client, discovers services/characteristics, and reads the temperature. The value is displayed in a declarative ArkUI interface, using `@State` for automatic updates and click handlers to connect or disconnect. This architecture separates BLE logic (`BleManager`) from UI logic (ArkUI `Index`), improving maintainability. This sample targets **API level 12**, using ArkTS capabilities available since OpenHarmony 3.1 (stage model).

After launching the app, with Bluetooth on and permissions granted, tap **"Connect"** to start BLE scanning. When the Temperature service server is found, the app automatically establishes a GATT connection. Within a few seconds you should see *Connected* and the temperature value (assuming the server populated the characteristic). The button label changes to **"Disconnect"**; pressing it again triggers disconnection, the status becomes *Disconnected* and the temperature shows *no data*. This basic BLE client can serve as a starting point for more advanced scenarios (multiple devices, pairing, notifications, additional characteristics), while the fundamentals-permissions, scanning, GATT connection, and reads-remain the same.