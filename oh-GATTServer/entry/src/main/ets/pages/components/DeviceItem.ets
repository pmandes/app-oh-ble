/**
 * DeviceItem – reusable row that represents a single BLE peripheral
 * in either the *paired* or *discovered* device list.
 * ---------------------------------------------------------------------------
 * The component is **presentational‑only**: it receives all data through
 * `@Param` props and notifies user actions through `@Event` callbacks. No BLE
 * logic or state mutations are performed inside; this keeps the UI layer thin
 * and easily testable.
 *
 * === Props (all decorated with @Param) ===
 * @param device            {DeviceInfo}  Full descriptor of the peripheral. Must
 *                                        at least contain `deviceId`, `name`,
 *                                        `isConnected`, and optionally `rssi`.
 * @param btEnabled         {boolean}     True when the Bluetooth adapter is ON;
 *                                        used to enable/disable the buttons.
 * @param isQuerying        {boolean}     True while a temperature request is in
 *                                        flight – disables the Temp button and
 *                                        shows an ellipsis label.
 * @param temperatureValue  {number|null} Last known temperature °C; `null` if
 *                                        not yet queried, `NaN` on error.
 * @param showRssi          {boolean}     If true, renders RSSI & deviceId under
 *                                        the device name (useful in the
 *                                        discovery list).
 * @param showTemperature   {boolean}     If true, renders the Get‑Temp area –
 *                                        used in the paired‑devices list.
 *
 * === Events ===
 * @event onConnectClick           () => void   Fired when user taps the
 *                                             Connect / Disconnect button.
 * @event onQueryTemperatureClick  () => void   Fired when user taps the
 *                                             Get‑Temp button.
 */

import { DeviceInfo } from '../../services/BleCentralService';

@ComponentV2
export struct DeviceItem {
  // ──────────────────────────────── Props ──────────────────────────────────
  @Param device: DeviceInfo = {} as DeviceInfo;
  @Param btEnabled: boolean = true;
  @Param isQuerying: boolean = false;
  @Param temperatureValue: number | null = null;
  @Param showRssi: boolean = false;
  @Param showTemperature: boolean = false;

  // ─────────────────────────────── Events ──────────────────────────────────
  @Event onConnectClick: () => void;
  @Event onQueryTemperatureClick: () => void;

  // ───────────────────────────────  UI  ────────────────────────────────────
  build(): void {
    Column() {
      /* Top row – device name, optional RSSI, Connect button */
      Row() {
        // Left side: name + optional RSSI / id line
        Column() {
          Text(this.device?.name || this.device?.deviceId)
            .fontSize(16)
            .textAlign(TextAlign.Start)

          // Show RSSI & deviceId only in discovery mode
          if (this.showRssi) {
            Text(`${this.device?.deviceId} · RSSI: ${this.device?.rssi}`)
              .fontSize(12)
              .opacity(0.7)
              .textAlign(TextAlign.Start)
          }
        }

        Column() {
          // Right side: Connect / Disconnect toggle
          Button(this.device?.isConnected ? 'Disconnect' : 'Connect')
            .onClick(() => this.onConnectClick())
            .enabled(this.btEnabled)// disabled when BT is OFF
            .width(120)
        }
        .alignSelf(ItemAlign.End)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      /* Temperature row – visible only for paired devices */
      if (this.showTemperature) {
        Row() {
          // Get‑Temp button – disabled while querying or when not connected
          Button(this.isQuerying ? '…' : 'Get Temp')
            .onClick(() => this.onQueryTemperatureClick())
            .enabled(this.device?.isConnected && !this.isQuerying)

          // Temperature value / error label
          if (this.temperatureValue !== null) {
            Text(
              isNaN(this.temperatureValue)
                ? 'Error'
                : `${this.temperatureValue.toFixed(1)} °C`
            )
          }
        }
      }
    }
    .padding(16)
    .backgroundColor('#eee')
    .borderRadius(8)
    .width('100%')
  }
}
