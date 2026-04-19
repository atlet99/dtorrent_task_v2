extension IntExtension on int {
  String toHexString() {
    return toRadixString(16).padLeft(2, '0');
  }
}

extension IterableExtensions on Iterable<int> {
  String toHexString({String empty = '', String separator = ''}) {
    return isEmpty ? empty : map((e) => e.toHexString()).join(separator);
  }
}
