import BleManager, {BleConnectionState} from '../ble/BleManager';

/**
 * Main entry component for the BLE Client application
 * Handles the UI and BLE connection management
 */
@Entry
@Component
struct Index {
  /** Instance of BLE manager for handling bluetooth operations */
  private bleManager: BleManager = new BleManager();

  /** Current temperature value from BLE device */
  @State temperature: number | null = null;

  /** Flag indicating if device is connected */
  @State connected: boolean = false;

  /** Current connection status text */
  @State status: string = "";

  /**
   * Lifecycle method called before the component appears
   * Sets up BLE callbacks for temperature and connection state changes
   */
  aboutToAppear() {
    console.debug(`[Index] aboutToAppear()`);

    // Set up temperature reading callback
    this.bleManager.setOnTemperatureRead(temp => {
      console.debug(`[Index] setOnTemperatureRead -> ${temp}`);
      this.temperature = temp;
    });

    // Set up connection state change callback
    this.bleManager.setOnConnectionChange(state => {
      console.debug(`[Index] setOnConnectionChange -> ${state}: ${BleConnectionState[state]}`);
      this.status = BleConnectionState[state];

      // Update connection state and clear temperature if disconnected
      if (state === BleConnectionState.Connected) {
        this.connected = true;
      } else {
        this.connected = false;
        this.temperature = null;
      }
    });
  }

  /**
   * Builds the UI component tree
   * Displays temperature, connection status, and control button
   */
  build() {
    RelativeContainer() {
      Column() {
        // Application title
        Text('BLE Client')
          .fontSize($r('app.float.page_text_font_size'))
          .fontWeight(FontWeight.Bold)

        // Connection control button
        Button(this.connected ? 'Disconnect' : 'Connect')
          .onClick(() => this.onConnectButtonClick())
          .margin(16)

        // Temperature display with emoji
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
      // Center alignment rules for the column
      .alignRules({
        center: { anchor: '__container__', align: VerticalAlign.Center },
        middle: { anchor: '__container__', align: HorizontalAlign.Center }
      })
    }
    .height('100%')
    .width('100%')
  }

  /**
   * Handles the Connect/Disconnect button click event
   * Toggles the BLE connection state based on current status:
   * - If connected: initiates disconnection
   * - If disconnected: initiates connection
   */
  private onConnectButtonClick(): void {
    console.debug(`[Index] onConnectButtonClick() -> connection state: ${this.connected}`);

    if (this.connected) {
      this.bleManager.disconnect();
    } else {
      this.bleManager.connect();
    }
  }
}
