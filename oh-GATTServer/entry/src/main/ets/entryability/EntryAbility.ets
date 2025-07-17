/**
 * EntryAbility.ets — Stage UIAbility bootstrap (API 12)
 * ====================================================
 *  • Requests Bluetooth- and Location-related permissions at startup.
 *  • Launches the single page `"pages/Index"` only after all permissions
 *    are granted.
 *  • Shows a short toast and terminates the app gracefully if the user
 *    denies any required permission or if a permission request fails.
 */

import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { Permissions } from '@ohos.abilityAccessCtrl';
import BleGattServer from '../services/BleGattServer';
import PermissionManager from '../permissions/PermissionManager';


const DOMAIN = 0x0000;               // hilog domain for structured logs

/**
 * Permissions required for BLE scanning/connection + coarse & fine location.
 * All five are mandatory on API 12 to perform full-featured BLE operations.
 */
const PERMS: Permissions[] = [
  'ohos.permission.USE_BLUETOOTH',
  'ohos.permission.DISCOVER_BLUETOOTH',
  'ohos.permission.ACCESS_BLUETOOTH',
  'ohos.permission.APPROXIMATELY_LOCATION',
  'ohos.permission.LOCATION'
];

/**
 * `EntryAbility` is the single entry point of the application.
 * It performs a permission-gate before loading the only UI page.
 */
export default class EntryAbility extends UIAbility {
  // ─────────────────────── Ability life-cycle overrides ────────────────────

  /** Ability is created but UI is not yet visible. */
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    super.onCreate(want, launchParam);
    hilog.info(DOMAIN, 'EntryAbility', 'onCreate');
  }

  /**
   * Stage-window is ready. Here we ask for runtime permissions and
   * load the main ArkUI page once the user grants them.
   */
  onWindowStageCreate(windowStage: window.WindowStage): void {
    super.onWindowStageCreate(windowStage);
    hilog.info(DOMAIN, 'EntryAbility', 'onWindowStageCreate: requesting permissions');

    const permissionManager = new PermissionManager();
    permissionManager.requestPermissions(this.context, PERMS, () => {

      // This callback runs only if all permissions are granted
      hilog.info(DOMAIN, 'EntryAbility', 'All permissions granted, loading main page');

      const gs: BleGattServer = new BleGattServer();

      gs.prepareGattServer().then(() => {
        hilog.info(DOMAIN, 'EntryAbility', 'Gatt server created');

        gs.startAdvertising();

      }).catch((reason: Error) => {
        hilog.error(DOMAIN, 'EntryAbility', `Error: ${reason.message}`);
      });


      windowStage.loadContent('pages/Index', loadErr => {
        if (loadErr && loadErr.code !== 0) {
          hilog.error(DOMAIN, 'EntryAbility', `loadContent failed: ${loadErr.code}`);
        } else {
          hilog.info(DOMAIN, 'EntryAbility', 'Main page loaded');
        }
      });
    });
  }

  /** Window stage is about to be destroyed (e.g., multitask close). */
  onWindowStageDestroy(): void {
    super.onWindowStageDestroy();
    hilog.info(DOMAIN, 'EntryAbility', 'onWindowStageDestroy');
  }

  /** Ability moved to foreground. */
  onForeground(): void {
    super.onForeground();
    hilog.info(DOMAIN, 'EntryAbility', 'onForeground');
  }

  /** Ability moved to background. */
  onBackground(): void {
    super.onBackground();
    hilog.info(DOMAIN, 'EntryAbility', 'onBackground');
  }

  /** Final clean-up before the process is torn down. */
  onDestroy(): void {
    super.onDestroy();
    hilog.info(DOMAIN, 'EntryAbility', 'onDestroy');
  }
}
