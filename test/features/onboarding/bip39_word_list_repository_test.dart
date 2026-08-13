import 'dart:convert';

import 'package:aster/core/core.dart';
import 'package:aster/features/onboarding/data/repository/repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads the pinned production BIP39 English list', () async {
    final result = await Bip39WordListRepository(rootBundle).load();

    expect(result, isA<AppSuccess<Bip39WordList>>());
    final words = (result as AppSuccess<Bip39WordList>).value;
    expect(words.length, Bip39WordListRepository.expectedWordCount);
    expect(words.contains('abandon'), isTrue);
    expect(words.contains('zoo'), isTrue);
    expect(words.contains('ABANDON'), isFalse);
  });

  test('rejects modified bytes before exposing any vocabulary', () async {
    final source = await rootBundle.loadString(
      Bip39WordListRepository.assetPath,
      cache: false,
    );
    final bundle = _MemoryAssetBundle(
      utf8.encode(source.replaceFirst('zoo', 'zap')),
    );

    final result = await Bip39WordListRepository(bundle).load();

    expect(result, isA<AppFailureResult<Bip39WordList>>());
    final failure = (result as AppFailureResult<Bip39WordList>).failure;
    expect(failure.code, 'bip39_word_list_unavailable');
    expect(failure.userMessage, isNot(contains('zap')));
  });

  test('shares a successful load across concurrent consumers', () async {
    final data = await rootBundle.load(Bip39WordListRepository.assetPath);
    final bundle = _MemoryAssetBundle(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    final repository = Bip39WordListRepository(bundle);

    final results = await Future.wait([repository.load(), repository.load()]);

    expect(results, everyElement(isA<AppSuccess<Bip39WordList>>()));
    expect(bundle.loadCount, 1);
  });
}

final class _MemoryAssetBundle extends CachingAssetBundle {
  _MemoryAssetBundle(List<int> bytes) : _bytes = Uint8List.fromList(bytes);

  final Uint8List _bytes;
  var loadCount = 0;

  @override
  Future<ByteData> load(String key) async {
    loadCount += 1;
    return ByteData.sublistView(_bytes);
  }
}
