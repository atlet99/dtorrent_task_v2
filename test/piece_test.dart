import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:test/test.dart';

void main() {
  group('Piece', () {
    test('rejects non-positive request length', () {
      expect(
        () => Piece('00' * 20, 0, 16, 0, requestLength: 0),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects request length larger than the protocol block size', () {
      expect(
        () => Piece(
          '00' * 20,
          0,
          defaultRequestLength * 2,
          0,
          requestLength: defaultRequestLength + 1,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('fails validation when piece data was not downloaded', () {
      final piece = Piece('00' * 20, 0, 16, 0);

      expect(piece.validatePiece, throwsStateError);
    });
  });
}
