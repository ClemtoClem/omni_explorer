import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omni_explorer/features/password_vault/services/secure_clipboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  String? clipboard;

  setUp(() {
    clipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          clipboard = (call.arguments as Map)['text'] as String?;
          return null;
        case 'Clipboard.getData':
          return clipboard == null ? null : {'text': clipboard};
      }
      return null;
    });
  });

  test('copie puis effacement automatique', () async {
    final c = SecureClipboard(
        clearAfter: const Duration(milliseconds: 50), useNative: false);
    await c.copy('secret');
    expect(clipboard, 'secret');
    expect(c.hasPendingClear, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(clipboard, '');
    expect(c.hasPendingClear, isFalse);
  });

  test('n\'efface pas une copie faite ensuite par l\'utilisateur', () async {
    final c = SecureClipboard(
        clearAfter: const Duration(milliseconds: 50), useNative: false);
    await c.copy('secret');
    clipboard = 'autre chose'; // copié depuis une autre application

    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(clipboard, 'autre chose');
  });

  test('effacement immédiat (verrouillage)', () async {
    final c = SecureClipboard(useNative: false);
    await c.copy('secret');
    await c.clearNow();
    expect(clipboard, '');
    expect(c.hasPendingClear, isFalse);
    c.dispose();
  });
}
