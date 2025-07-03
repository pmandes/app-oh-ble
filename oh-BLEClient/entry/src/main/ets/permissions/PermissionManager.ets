import abilityAccessCtrl, { Permissions, PermissionRequestResult } from '@ohos.abilityAccessCtrl';
import { BusinessError } from '@ohos.base';
import promptAction from '@ohos.promptAction';
import { hilog } from '@kit.PerformanceAnalysisKit';
import common from '@ohos.app.ability.common';

/**
 * PermissionManager handles runtime permission requests for the application.
 * It requests the required permissions from the user and ensures all are granted
 * before allowing the app to continue. If any permission is denied or a request
 * fails, it logs the error, shows a toast, and terminates the app.
 *
 * This class is designed for OpenHarmony 5.0 (API 12) stage model (ArkUI TS) and
 * can be reused to request any set of permissions.
 */
export default class PermissionManager {

  private static readonly DOMAIN: number = 0x0000;  // Logging domain (same as in EntryAbility)
  private atManager = abilityAccessCtrl.createAtManager();  // Permission request manager

  /**
   * Requests the given permissions from the user and handles the response.
   * @param context - The UIAbility context used to make the permission request and to terminate the ability if needed.
   * @param permissions - An array of permission strings to request from the user.
   * @param onAllGranted - Callback invoked if **all** requested permissions are granted. This is where the caller can continue app initialization.
   */
  requestPermissions(
    context: common.UIAbilityContext,
    permissions: Permissions[],
    onAllGranted: () => void
  ): void {

    hilog.info(PermissionManager.DOMAIN, 'PermissionManager', 'Requesting permissions from user');

    this.atManager.requestPermissionsFromUser(
      context,
      permissions,
      (err: BusinessError | null, result: PermissionRequestResult | undefined): void => {

        hilog.info(PermissionManager.DOMAIN, 'PermissionManager', 'Permission callback invoked');

        // --- Error handling branch ---
        if (err) {

          hilog.error(PermissionManager.DOMAIN, 'PermissionManager', `Permission request error: ${err.code}`);

          promptAction.showToast({ message: 'Error requesting permissions. Closing app.' });
          // Terminate the ability after a short delay
          setTimeout(():Promise<void> => context.terminateSelf(), 1_500);
          return;
        }

        if (!result) {

          hilog.error(PermissionManager.DOMAIN, 'PermissionManager', 'Permission result is undefined');

          setTimeout(():Promise<void> => context.terminateSelf(), 1_500);
          return;
        }

        // --- Success handling branch ---
        hilog.info(PermissionManager.DOMAIN, 'PermissionManager', 'Permissions callback received');

        // Log each permission and its grant status
        const permsList: string[] = result.permissions;
        const authResults: number[] = result.authResults;

        for (let i = 0; i < permsList.length; i++) {
          hilog.info(
            PermissionManager.DOMAIN, 'PermissionManager',
            `perm=${permsList[i]}, status=${authResults[i]}`
          );
        }

        // Check if every permission is granted
        const allGranted: boolean = authResults.every(
          status => status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED
        );

        if (!allGranted) {

          hilog.info(PermissionManager.DOMAIN, 'PermissionManager', 'Not all permissions granted, closing app');

          promptAction.showToast({ message: 'Permissions denied – closing.' });
          setTimeout(():Promise<void> => context.terminateSelf(), 1_500);
          return;
        }

        hilog.info(PermissionManager.DOMAIN, 'PermissionManager', 'All permissions granted');

        // All permissions are granted – invoke the callback to continue app initialization
        onAllGranted();
      }
    );
  }
}
