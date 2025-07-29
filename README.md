# app-oh-ble
BLE GATT client/server

## 1. Introduction – BLE and GATT

**Bluetooth Low Energy (BLE)** is a flavour of the **Bluetooth** technology built for ultra‑low power consumption. It operates in the 2.4 GHz ISM band, keeps its radio active for very short intervals and therefore enables battery‑powered devices to run for months or even years. The power efficiency comes at the cost of lower throughput (≈1 Mb/s) and smaller frame sizes compared to classic **Bluetooth**.

**The Generic Attribute Profile (GATT)** sits on top of the [ATT protocol](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/Core-54/out/en/host/attribute-protocol--att-.html) in the **BLE** stack. It defines a hierarchy of services and characteristics plus the procedures for discovering, reading, writing, notifying and indicating those characteristics. **GATT** follows a strict client/server model: a client device (e.g. a smartphone) issues requests to the server (peripheral), while the server replies with data or pushes notifications.
