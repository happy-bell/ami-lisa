import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:amiapp/appdefine.dart';
import 'package:amiapp/helpers/widget_util.dart';
import 'package:amiapp/pages/setting/setting_args.dart';
import 'package:amiapp/pages/elan/setting/elan_input_user_name_page.dart';
import 'package:amiapp/services/appmanager.dart';

class ElanCropImagePage extends StatefulWidget {
  XFile pickedFile;
  ElanCropImagePage({Key? key, required this.pickedFile});

  @override
  ElanCropImagePageState createState() => ElanCropImagePageState();
}

class ElanCropImagePageState extends State<ElanCropImagePage> {
  bool _loading = false;
  var title = '';
  var _init = true;
  List<dynamic> _data = [];
  final ImagePicker _picker = ImagePicker();
  dynamic _changeImageUser;
  XFile? _pickedFile;
  CroppedFile? _croppedFile;

  @override
  void initState() {
    super.initState();
  }

  void _close() {

  }


  Future<void> _cropImage() async {
    final croppedFile = await ImageCropper().cropImage(
      sourcePath: widget.pickedFile.path,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 100,
      aspectRatio: const CropAspectRatio(ratioX: 4, ratioY: 3),
      uiSettings: [
        AndroidUiSettings(
            toolbarTitle: 'Cropper',
            toolbarColor: Colors.deepOrange,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false),
        IOSUiSettings(
          title: 'サイズ指定',
          rotateButtonsHidden: true,
          resetButtonHidden: true,
          aspectRatioPickerButtonHidden: true,
          aspectRatioLockEnabled: true,
          doneButtonTitle: '決定',
          cancelButtonTitle: 'キャンセル',
        ),
        WebUiSettings(
          context: context,
          presentStyle: CropperPresentStyle.dialog,
          boundary: const CroppieBoundary(
            width: 520,
            height: 520,
          ),
          viewPort:
          const CroppieViewPort(width: 480, height: 480, type: 'circle'),
          enableExif: true,
          enableZoom: true,
          showZoomer: true,
        ),
      ],
    );
    if (croppedFile != null) {
      setState(() {
        _croppedFile = croppedFile;
      });
    }
  }

  Widget _image() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final path = widget.pickedFile.path;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 0.8 * screenWidth,
        maxHeight: 0.7 * screenHeight,
      ),
      child: Image.file(File(path)),
    );
  }

  Widget _menu() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_croppedFile != null)
          FloatingActionButton(
            onPressed: () {
              _close();
            },
            backgroundColor: Colors.redAccent,
            tooltip: 'キャンセル',
            child: const Icon(Icons.close),
          ),
        if (_croppedFile == null)
          Padding(
            padding: const EdgeInsets.only(left: 32.0),
            child: FloatingActionButton(
              onPressed: () {
                _cropImage();
              },
              backgroundColor: const Color(0xFFBC764A),
              tooltip: 'Crop',
              child: const Icon(Icons.crop),
            ),
          )
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('画像編集'),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Padding(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Card(
                      elevation: 4.0,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: _image(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24.0),
                  _menu(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
