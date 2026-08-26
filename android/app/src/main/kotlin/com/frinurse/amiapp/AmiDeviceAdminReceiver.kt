package jp.amiplus.lisa

import android.app.admin.DeviceAdminReceiver

/**
 * 通話終了後に「TV電源オフ(画面オフ)状態へ戻す」ため、DevicePolicyManager.lockNow() を
 * 使えるようにするデバイス管理レシーバー。TV005のみで使用（判定は [TvStandbyController]）。
 *
 * ポリシーは force-lock のみ（res/xml/ami_device_admin.xml）。パスワード強制やワイプ等は行わない。
 *
 * ※このファイルは ami_tv には存在しない独自追加ファイルのため、同期(rsync)で上書きされない。
 */
class AmiDeviceAdminReceiver : DeviceAdminReceiver()
