import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:amiapp/models/address_model.dart';
import 'package:amiapp/notifiers/address_notifier.dart';
import 'package:amiapp/services/appmanager.dart';
import 'package:amiapp/widgets/tv_pi_focus_button.dart';

/// 46amip4 `#open01` 相当。同じコードの他ユーザーから相手を選んで呼び出す。
class TvPiAddressListDialog extends StatelessWidget {
  const TvPiAddressListDialog({
    super.key,
    required this.statusReady,
    this.familyName = '',
  });

  final ValueListenable<bool> statusReady;
  final String familyName;

  static List<Address> targets(
    List<Address> all, {
    required bool statusReady,
    String familyName = '',
  }) {
    final mine = AppManager.myId;
    final list = <Address>[];
    if (familyName.isNotEmpty &&
        !all.any((a) => a.id.contains('%F%'))) {
      list.add(Address(
        id: '$mine%F%',
        name: familyName,
        code: AppManager.delegatorCode,
        type: 'family',
        status: 0,
        call: 0,
        called: 0,
        userType: 'F',
        photo: '',
      ));
    }
    for (final address in all) {
      if (address.id == mine) continue;
      if (address.id.startsWith('@')) continue;
      if (statusReady && !_isCallable(address)) continue;
      list.add(address);
    }
    return list;
  }

  static bool _isCallable(Address address) {
    if (address.id.contains('%F%') || address.userType == 'F') {
      return true;
    }
    return address.status != -1;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: statusReady,
      builder: (context, ready, _) {
        final store = context.watch<AddressStore>();
        final list = targets(
          store.addressList,
          statusReady: ready,
          familyName: familyName,
        );
        return _panel(context, list);
      },
    );
  }

  Widget _panel(BuildContext context, List<Address> list) {
    return Material(
      color: Colors.black54,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.6,
              maxHeight: MediaQuery.of(context).size.height * 0.82,
            ),
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                children: [
                  const Text(
                    'テレビ電話',
                    style: TextStyle(
                      color: Color(0xFF72BB2A),
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: list.isEmpty
                        ? const Center(
                            child: Text(
                              'オンラインの相手がいません',
                              style: TextStyle(
                                fontSize: 22,
                                color: Color(0xFF333333),
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: list.length,
                            itemBuilder: (context, index) {
                              final address = list[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: TvPiFocusButton(
                                  label: address.name,
                                  autofocus: index == 0,
                                  fontSize: 22,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                    horizontal: 10,
                                  ),
                                  onPressed: () =>
                                      Navigator.of(context).pop(address),
                                ),
                              );
                            },
                          ),
                  ),
                  TvPiFocusButton(
                    label: '閉じる',
                    autofocus: list.isEmpty,
                    color: const Color(0xFF03964B),
                    fontSize: 22,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
