/// Minimal handle for writing torrent file data.
abstract interface class SecureFileWriter {
  void write(int offset, List<int> data, int start, int end);

  void flush();

  void close();
}
