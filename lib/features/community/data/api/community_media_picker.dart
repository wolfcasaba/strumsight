/// Kép-választó a közösségi szerkesztőhöz (javító sáv R27).
///
/// Egy port és egy adapter. A port azért kell, mert a szerkesztő
/// widget-tesztje nem nyithat platform-párbeszédet; az adapter azért
/// ilyen vékony, mert MINDEN érdemi döntés a szerveren születik.
///
/// **Miért `file_selector`, és miért NEM `image_picker`.** A fa már
/// szállítja a `file_selector`-t (Song Trainer kottaválasztó, E26-R26
/// hang-import), és ugyanezt tudja: a felhasználó kiválaszt egy fájlt,
/// mi bájtokat kapunk. Egy MÁSODIK választó-plugin behúzása új
/// tranzitív függvény-halmazt (és egy új `win32`-major kockázatot) hozna
/// a fába azért, amit a meglévő is megold — a fenntartott
/// „egy plugin egy képességre" szabály (`analysis_audio_file_picker.dart`
/// fejléce) pontosan ezért létezik.
///
/// **A kiterjesztés-lista nem biztonsági határ.** A választóablak
/// SZŰKÍTŐ segítség a felhasználónak, semmi több: a szerver a bájtokból
/// dönt (`backend/app/community/media/sniff.py`), és egy `.jpg`-re
/// átnevezett SVG-t a lista sem itt, sem ott nem engedne át. A kliens
/// ezért nem is „ellenőriz" — ami átcsúszik, azt a szerver utasítja el,
/// és a felhasználó a lokalizált elutasítási okot kapja.
library;

import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

/// Egy kiválasztott fájl, már memóriában.
///
/// A plugin `XFile`-ja nem lépi át ezt a határt: az application réteg
/// bájtokat és egy megjelenítendő nevet kap, tehát sem platform-objektum,
/// sem fájlrendszer-útvonal nem kerül provider-állapotba vagy egy
/// perzisztált dokumentumba.
final class PickedCommunityMedia {
  PickedCommunityMedia({required this.displayName, required List<int> bytes})
    : bytes = Uint8List.fromList(bytes);

  /// A fájlnév, ahogy az OS mondta. KIZÁRÓLAG megjelenítésre — a
  /// szerverre nem ez megy ki (l. `ApiClient.postMultipartJson`).
  final String displayName;

  final Uint8List bytes;
}

/// Platform-határ a közösségi kép-választáshoz.
abstract interface class CommunityMediaPicker {
  /// A kiválasztott kép, vagy `null`, ha a felhasználó megszakította.
  Future<PickedCommunityMedia?> pickImage();
}

/// Éles adapter a `file_selector` fölött.
final class PlatformCommunityMediaPicker implements CommunityMediaPicker {
  const PlatformCommunityMediaPicker();

  /// Amit a párbeszéd FELKÍNÁL. A három formátum ugyanaz a három,
  /// amelyet a szerver kép-oldali allowlistája elfogad
  /// (`sniff.py`: `image/jpeg`, `image/png`, `image/webp`) — így a
  /// felhasználó nem tud olyat választani, amit a szerver garantáltan
  /// visszautasít, de a lista attól még nem VÉDELEM.
  static const List<String> offeredExtensions = <String>[
    'jpg',
    'jpeg',
    'png',
    'webp',
  ];

  static const List<String> offeredMimeTypes = <String>[
    'image/jpeg',
    'image/png',
    'image/webp',
  ];

  static const XTypeGroup _imageTypeGroup = XTypeGroup(
    label: 'StrumSight community image',
    extensions: offeredExtensions,
    mimeTypes: offeredMimeTypes,
  );

  @override
  Future<PickedCommunityMedia?> pickImage() async {
    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[_imageTypeGroup],
    );
    if (file == null) return null;
    return PickedCommunityMedia(
      displayName: file.name,
      bytes: await file.readAsBytes(),
    );
  }
}
