import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:amiapp/notifiers/address_notifier.dart';

class SettingUserPage extends StatefulWidget {
  const SettingUserPage({super.key});

  @override
  _SettingUserPageState createState() => _SettingUserPageState();
}

class _SettingUserPageState extends State<SettingUserPage> {
  bool _init = true;
  List<List<String>> data = [];

  final _listHeight = 44.0;
  final TextStyle _titleTextStyle1 = const TextStyle(
    fontSize: 14,
  );

  @override
  void initState() {
    super.initState();
    print('setting user  initState');
  }

  @override
  void didChangeDependencies() async {
    super.didChangeDependencies();
    print('setting user didChangeDependencies');

    if (_init) {
      _init = false;
      data = context.read<AddressStore>().list('3');
      setState(() {

      });
    }
  }

  Widget listContainer(String udid, String name) {
    return InkWell(
      onTap: () async {
        // final args = SettingArguments();
        // args.key = udid;
        // args.value = name;
        // await Navigator.of(context)
        //     .pushNamed('/settingautoreceive', arguments: args);
      },
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            bottom: BorderSide(color: Color.fromARGB(255, 220, 220, 220)),
          ),
        ),
        height: _listHeight,
        // margin: const EdgeInsets.all(0.0),
        padding: const EdgeInsets.all(10.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              name,
              style: _titleTextStyle1,
            ),
            const Icon(
              Icons.arrow_forward_ios,
              color: Colors.grey,
              size: 18.0,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('自動応答個別設定'),
      ),
      body: ListView.builder(
        itemBuilder: (BuildContext context, int index) {
          return listContainer(data[index][0], data[index][1]);
        },
        itemCount: data.length,
      ),
    );
  }
}
