import 'dart:typed_data';

enum InflateFailureKind { truncated, invalidBlockType, invalidStoredLength, invalidCode, invalidDistance, tooLarge }

final class InflateFailure implements Exception {
  const InflateFailure(this.kind);

  final InflateFailureKind kind;

  @override
  String toString() => 'InflateFailure(${kind.name})';
}

final class _Huffman {
  _Huffman(List<int> lengths) : symbol = List.filled(lengths.length, 0) {
    for (final length in lengths) {
      count[length] += 1;
    }
    final offsets = List.filled(16, 0);
    for (var length = 1; length < 15; length++) {
      offsets[length + 1] = offsets[length] + count[length];
    }
    for (var value = 0; value < lengths.length; value++) {
      final length = lengths[value];
      if (length == 0) continue;
      symbol[offsets[length]] = value;
      offsets[length] += 1;
    }
  }

  /// Anzahl der Codes je Länge (0…15).
  final List<int> count = List.filled(16, 0);

  /// Symbole nach Code sortiert.
  final List<int> symbol;
}

/// Entpackt DEFLATE-Daten (RFC 1951, ohne zlib-Kopf), wie sie in ZIP-Dateien stecken. Port der eigenen Umsetzung aus
/// Swift (nach Mark Adlers `puff.c`), damit kaputte Daten genauso erkannt werden.
abstract final class InflateData {
  /// Obergrenze gegen kaputte oder bösartige Daten (eine FIT-Datei hat selten mehr als ein paar MB).
  static const maxOutput = 64 * 1024 * 1024;

  static final _fixedLengths = _Huffman([
    for (var index = 0; index < 288; index++)
      index < 144
          ? 8
          : index < 256
          ? 9
          : index < 280
          ? 7
          : 8,
  ]);
  static final _fixedDistances = _Huffman(List.filled(30, 5));

  static const _lengthBase = [
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    13,
    15,
    17,
    19,
    23,
    27,
    31,
    35,
    43,
    51,
    59,
    67,
    83,
    99,
    115,
    131,
    163,
    195,
    227,
    258, //
  ];
  static const _lengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0];
  static const _distanceBase = [
    1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, //
    6145, 8193, 12289, 16385, 24577,
  ];
  static const _distanceExtra = [
    0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13, //
  ];

  /// Reihenfolge der Codelängen-Codes im dynamischen Block.
  static const _codeLengthOrder = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15];

  static Uint8List decompress(List<int> data) {
    final state = _State(data);
    var last = false;
    while (!last) {
      last = state.bits(1) == 1;
      switch (state.bits(2)) {
        case 0:
          state.stored();
        case 1:
          state.codes(_fixedLengths, _fixedDistances);
        case 2:
          state.dynamic();
        default:
          throw const InflateFailure(InflateFailureKind.invalidBlockType);
      }
    }
    return Uint8List.fromList(state.output);
  }
}

final class _State {
  _State(this.input);

  final List<int> input;
  int position = 0;
  int bitBuffer = 0;
  int bitCount = 0;
  final List<int> output = [];

  int bits(int needed) {
    var value = bitBuffer;
    while (bitCount < needed) {
      if (position >= input.length) throw const InflateFailure(InflateFailureKind.truncated);
      value |= input[position] << bitCount;
      position += 1;
      bitCount += 8;
    }
    bitBuffer = value >> needed;
    bitCount -= needed;
    return value & ((1 << needed) - 1);
  }

  void stored() {
    bitBuffer = 0;
    bitCount = 0;
    if (position + 4 > input.length) throw const InflateFailure(InflateFailureKind.truncated);
    final length = input[position] | input[position + 1] << 8;
    final complement = input[position + 2] | input[position + 3] << 8;
    if (length != (~complement & 0xFFFF)) throw const InflateFailure(InflateFailureKind.invalidStoredLength);
    position += 4;
    if (position + length > input.length) throw const InflateFailure(InflateFailureKind.truncated);
    if (output.length + length > InflateData.maxOutput) throw const InflateFailure(InflateFailureKind.tooLarge);
    output.addAll(input.sublist(position, position + length));
    position += length;
  }

  int decode(_Huffman huffman) {
    var code = 0;
    var first = 0;
    var index = 0;
    for (var length = 1; length <= 15; length++) {
      code |= bits(1);
      final count = huffman.count[length];
      if (code - count < first) return huffman.symbol[index + (code - first)];
      index += count;
      first += count;
      first <<= 1;
      code <<= 1;
    }
    throw const InflateFailure(InflateFailureKind.invalidCode);
  }

  void codes(_Huffman lengths, _Huffman distances) {
    while (true) {
      final symbol = decode(lengths);
      if (symbol < 256) {
        if (output.length >= InflateData.maxOutput) throw const InflateFailure(InflateFailureKind.tooLarge);
        output.add(symbol);
        continue;
      }
      if (symbol == 256) return;
      final lengthIndex = symbol - 257;
      if (lengthIndex >= InflateData._lengthBase.length) throw const InflateFailure(InflateFailureKind.invalidCode);
      final length = InflateData._lengthBase[lengthIndex] + bits(InflateData._lengthExtra[lengthIndex]);
      final distanceSymbol = decode(distances);
      if (distanceSymbol >= InflateData._distanceBase.length) {
        throw const InflateFailure(InflateFailureKind.invalidDistance);
      }
      final distance = InflateData._distanceBase[distanceSymbol] + bits(InflateData._distanceExtra[distanceSymbol]);
      if (distance > output.length) throw const InflateFailure(InflateFailureKind.invalidDistance);
      if (output.length + length > InflateData.maxOutput) throw const InflateFailure(InflateFailureKind.tooLarge);
      final start = output.length - distance;
      // Überlappende Kopie ist erlaubt (z. B. Abstand 1 = Wiederholung).
      for (var offset = 0; offset < length; offset++) {
        output.add(output[start + offset]);
      }
    }
  }

  void dynamic() {
    final literalCount = bits(5) + 257;
    final distanceCount = bits(5) + 1;
    final codeCount = bits(4) + 4;
    if (literalCount > 286 || distanceCount > 30) throw const InflateFailure(InflateFailureKind.invalidCode);
    final codeLengths = List.filled(19, 0);
    for (var index = 0; index < codeCount; index++) {
      codeLengths[InflateData._codeLengthOrder[index]] = bits(3);
    }
    final codeLengthCode = _Huffman(codeLengths);
    final lengths = <int>[];
    while (lengths.length < literalCount + distanceCount) {
      final symbol = decode(codeLengthCode);
      if (symbol < 16) {
        lengths.add(symbol);
      } else if (symbol == 16) {
        if (lengths.isEmpty) throw const InflateFailure(InflateFailureKind.invalidCode);
        final previous = lengths.last;
        lengths.addAll(List.filled(3 + bits(2), previous));
      } else if (symbol == 17) {
        lengths.addAll(List.filled(3 + bits(3), 0));
      } else {
        lengths.addAll(List.filled(11 + bits(7), 0));
      }
    }
    if (lengths.length != literalCount + distanceCount || lengths[256] == 0) {
      throw const InflateFailure(InflateFailureKind.invalidCode);
    }
    codes(_Huffman(lengths.sublist(0, literalCount)), _Huffman(lengths.sublist(literalCount)));
  }
}
