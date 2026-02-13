class CellData {
  CellData({
    required this.foreground,
    required this.background,
    required this.flags,
    required this.content,
  });

  factory CellData.empty() {
    return CellData(
      foreground: 0,
      background: 0,
      flags: 0,
      content: 0,
    );
  }

  int foreground;

  int background;

  int flags;

  int content;

  @pragma('vm:prefer-inline')
  int getHash() {
    // Inline Jenkins hash for 4 int values — avoids boxing from Object? params
    var h = 0;
    h = 0x1fffffff & (h + foreground);
    h = 0x1fffffff & (h + ((0x0007ffff & h) << 10));
    h = h ^ (h >> 6);
    h = 0x1fffffff & (h + background);
    h = 0x1fffffff & (h + ((0x0007ffff & h) << 10));
    h = h ^ (h >> 6);
    h = 0x1fffffff & (h + flags);
    h = 0x1fffffff & (h + ((0x0007ffff & h) << 10));
    h = h ^ (h >> 6);
    h = 0x1fffffff & (h + content);
    h = 0x1fffffff & (h + ((0x0007ffff & h) << 10));
    h = h ^ (h >> 6);
    h = 0x1fffffff & (h + ((0x03ffffff & h) << 3));
    h = h ^ (h >> 11);
    return 0x1fffffff & (h + ((0x00003fff & h) << 15));
  }

  @override
  String toString() {
    return 'CellData{foreground: $foreground, background: $background, flags: $flags, content: $content}';
  }
}

abstract class CellAttr {
  static const bold = 1 << 0;
  static const faint = 1 << 1;
  static const italic = 1 << 2;
  static const underline = 1 << 3;
  static const blink = 1 << 4;
  static const inverse = 1 << 5;
  static const invisible = 1 << 6;
  static const strikethrough = 1 << 7;
}

abstract class CellColor {
  static const valueMask = 0xFFFFFF;

  static const typeShift = 25;
  static const typeMask = 3 << typeShift;

  static const normal = 0 << typeShift;
  static const named = 1 << typeShift;
  static const palette = 2 << typeShift;
  static const rgb = 3 << typeShift;
}

abstract class CellContent {
  static const codepointMask = 0x1fffff;

  static const widthShift = 22;
  // static const widthMask = 3 << widthShift;
}
