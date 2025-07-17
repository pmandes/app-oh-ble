
@ComponentV2
export struct AppHeader {

  @Param isScanning: boolean = false;

  @Param btEnabled: boolean = false;

  @Event onScanBtnClick: () => void;

  build(): void {
    Row() {
      // Title text
      Text('BLE Scanner')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .margin({ right: 20 });

      // Scan / Stop button
      Button(this.isScanning ? 'Stop' : 'Scan')
        .enabled(this.btEnabled)
        .opacity(this.btEnabled ? 1 : 0.4)
        .onClick(() => this.onButtonClick());
    }
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
    .padding({ top: 12, bottom: 12, left: 16, right: 16 });
  }

  onButtonClick() {
    console.debug(`onScanButtonClick() -> btEnabled: ${ this.btEnabled }, isScanning: ${ this.isScanning }`);

    if (!this.btEnabled) return;
    this.onScanBtnClick();
  }
}
