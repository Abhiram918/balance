import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;

/// Fast, standalone parser for Windows Shell Link (.lnk) binary files.
/// Conforms to Microsoft [MS-SHLLINK] specification.
/// Does not depend on Win32 COM, making it lightweight, fast, crash-resilient,
/// and fully testable across test environments.
class LnkResolver {
  /// Resolves the target executable path and optional icon location from a [.lnk] file.
  static LnkResolution? resolve(File file) {
    try {
      if (!file.existsSync()) return null;
      final bytes = file.readAsBytesSync();
      return resolveBytes(bytes, lnkDirectory: file.parent.path);
    } catch (_) {
      return null;
    }
  }

  /// Parses binary bytes of a [.lnk] file.
  static LnkResolution? resolveBytes(Uint8List bytes, {String? lnkDirectory}) {
    if (bytes.length < 76) return null;
    final byteData = ByteData.sublistView(bytes);

    // 1. Verify Shell Link Header: HeaderSize must be 0x0000004C (76 bytes)
    final headerSize = byteData.getUint32(0, Endian.little);
    if (headerSize != 0x4C) return null;

    final flags = byteData.getUint32(20, Endian.little);
    final hasTargetIdList = (flags & 0x01) != 0;
    final hasLinkInfo = (flags & 0x02) != 0;
    final hasName = (flags & 0x04) != 0;
    final hasRelativePath = (flags & 0x08) != 0;
    final hasWorkingDir = (flags & 0x10) != 0;
    final hasArguments = (flags & 0x20) != 0;
    final hasIconLocation = (flags & 0x40) != 0;
    final isUnicode = (flags & 0x80) != 0;

    int offset = 76;

    // 2. Skip LinkTargetIDList if present
    if (hasTargetIdList) {
      if (offset + 2 > bytes.length) return null;
      final idListSize = byteData.getUint16(offset, Endian.little);
      offset += 2 + idListSize;
    }

    String? targetPath;

    // 3. Parse LinkInfo if present
    if (hasLinkInfo && offset + 4 <= bytes.length) {
      final linkInfoStart = offset;
      final linkInfoSize = byteData.getUint32(linkInfoStart, Endian.little);

      if (linkInfoSize >= 28 && linkInfoStart + linkInfoSize <= bytes.length) {
        final linkInfoHeaderSize = byteData.getUint32(linkInfoStart + 4, Endian.little);
        final linkInfoFlags = byteData.getUint32(linkInfoStart + 8, Endian.little);
        final hasLocalBasePath = (linkInfoFlags & 0x01) != 0;

        if (hasLocalBasePath) {
          // Check for Unicode local base path (LinkInfoHeaderSize >= 0x24 / 36 bytes)
          if (linkInfoHeaderSize >= 0x24 && linkInfoStart + 32 <= bytes.length) {
            final unicodeOffset = byteData.getUint32(linkInfoStart + 28, Endian.little);
            if (unicodeOffset > 0 && linkInfoStart + unicodeOffset < bytes.length) {
              final rawPath = _readNullTerminatedUtf16(bytes, linkInfoStart + unicodeOffset);
              if (rawPath.isNotEmpty) {
                targetPath = cleanPath(rawPath);
              }
            }
          }

          // Fallback to ANSI local base path
          if (targetPath == null) {
            final localBasePathOffset = byteData.getUint32(linkInfoStart + 16, Endian.little);
            if (localBasePathOffset > 0 && linkInfoStart + localBasePathOffset < bytes.length) {
              final rawPath = _readNullTerminatedAnsi(bytes, linkInfoStart + localBasePathOffset);
              if (rawPath.isNotEmpty) {
                targetPath = cleanPath(rawPath);
              }
            }
          }
        }
      }

      offset += linkInfoSize;
    }

    // 4. Parse StringData blocks if needed
    String? nameString;
    String? relativePathString;
    String? iconLocationString;

    try {
      if (hasName && offset < bytes.length) {
        final res = _readCountedString(bytes, offset, isUnicode);
        nameString = res.value;
        offset = res.nextOffset;
      }
      if (hasRelativePath && offset < bytes.length) {
        final res = _readCountedString(bytes, offset, isUnicode);
        relativePathString = res.value;
        offset = res.nextOffset;
      }
      if (hasWorkingDir && offset < bytes.length) {
        final res = _readCountedString(bytes, offset, isUnicode);
        offset = res.nextOffset;
      }
      if (hasArguments && offset < bytes.length) {
        final res = _readCountedString(bytes, offset, isUnicode);
        offset = res.nextOffset;
      }
      if (hasIconLocation && offset < bytes.length) {
        final res = _readCountedString(bytes, offset, isUnicode);
        iconLocationString = res.value;
        offset = res.nextOffset;
      }
    } catch (_) {
      // Continue with best effort
    }

    // Resolve relative path if targetPath not found or if targetPath doesn't exist
    if ((targetPath == null || !File(targetPath).existsSync()) &&
        relativePathString != null &&
        relativePathString.isNotEmpty &&
        lnkDirectory != null) {
      final joined = p.normalize(p.join(lnkDirectory, relativePathString));
      if (File(joined).existsSync()) {
        targetPath = joined;
      }
    }

    // 5. Heuristic search: look for embedded drive letter path (C:\...) in raw bytes
    if (targetPath == null || !File(targetPath).existsSync()) {
      // Search for UTF-16 path (e.g. C:\)
      for (int i = 0; i < bytes.length - 8; i += 2) {
        if (bytes[i + 2] == 0x3A && bytes[i + 3] == 0 && bytes[i + 4] == 0x5C && bytes[i + 5] == 0) {
          final candidate = _readNullTerminatedUtf16(bytes, i);
          if (candidate.toLowerCase().endsWith('.exe')) {
            final cleaned = cleanPath(candidate);
            if (File(cleaned).existsSync()) {
              targetPath = cleaned;
              break;
            }
          }
        }
      }
    }

    if (targetPath == null || !File(targetPath).existsSync()) {
      // Search for ANSI path (e.g. C:\)
      for (int i = 0; i < bytes.length - 10; i++) {
        if (bytes[i + 1] == 0x3A && bytes[i + 2] == 0x5C) {
          final driveChar = String.fromCharCode(bytes[i]);
          if (RegExp(r'[a-zA-Z]').hasMatch(driveChar)) {
            final candidate = _readNullTerminatedAnsi(bytes, i);
            if (candidate.toLowerCase().endsWith('.exe')) {
              final cleaned = cleanPath(candidate);
              if (File(cleaned).existsSync()) {
                targetPath = cleaned;
                break;
              }
            }
          }
        }
      }
    }

    if (targetPath == null) return null;

    String? cleanedIcon;
    if (iconLocationString != null && iconLocationString.isNotEmpty) {
      cleanedIcon = cleanPath(iconLocationString);
      if (!File(cleanedIcon).existsSync()) {
        cleanedIcon = null;
      }
    }

    return LnkResolution(
      targetPath: targetPath,
      name: nameString,
      iconLocation: cleanedIcon,
    );
  }

  /// Cleans quotes and expands environment variables in path string.
  static String expandEnvVars(String raw) => cleanPath(raw);

  /// Cleans quotes and expands environment variables in path string.
  static String cleanPath(String raw) {
    var s = raw.trim();
    if (s.startsWith('"') && s.endsWith('"') && s.length >= 2) {
      s = s.substring(1, s.length - 1).trim();
    }

    if (s.contains('%')) {
      s = s.replaceAllMapped(RegExp(r'%([^%]+)%'), (m) {
        final varName = m.group(1)!;
        return Platform.environment[varName] ??
            Platform.environment[varName.toUpperCase()] ??
            m.group(0)!;
      });
    }

    return p.normalize(s);
  }

  static String _readNullTerminatedAnsi(Uint8List bytes, int start) {
    int end = start;
    while (end < bytes.length && bytes[end] != 0 && bytes[end] >= 32 && bytes[end] <= 126) {
      end++;
    }
    return String.fromCharCodes(bytes.sublist(start, end));
  }

  static String _readNullTerminatedUtf16(Uint8List bytes, int start) {
    final codeUnits = <int>[];
    for (int i = start; i + 1 < bytes.length; i += 2) {
      final val = bytes[i] | (bytes[i + 1] << 8);
      if (val == 0 || val < 32) break;
      codeUnits.add(val);
    }
    return String.fromCharCodes(codeUnits);
  }

  static _CountedString _readCountedString(Uint8List bytes, int offset, bool isUnicode) {
    if (offset + 2 > bytes.length) {
      return _CountedString('', bytes.length);
    }
    final byteData = ByteData.sublistView(bytes);
    final count = byteData.getUint16(offset, Endian.little);
    final strStart = offset + 2;

    if (isUnicode) {
      final strBytesLen = count * 2;
      if (strStart + strBytesLen > bytes.length) {
        return _CountedString('', bytes.length);
      }
      final codeUnits = <int>[];
      for (int i = strStart; i < strStart + strBytesLen; i += 2) {
        codeUnits.add(bytes[i] | (bytes[i + 1] << 8));
      }
      return _CountedString(String.fromCharCodes(codeUnits), strStart + strBytesLen);
    } else {
      if (strStart + count > bytes.length) {
        return _CountedString('', bytes.length);
      }
      return _CountedString(
        String.fromCharCodes(bytes.sublist(strStart, strStart + count)),
        strStart + count,
      );
    }
  }
}

class LnkResolution {
  final String targetPath;
  final String? name;
  final String? iconLocation;

  const LnkResolution({
    required this.targetPath,
    this.name,
    this.iconLocation,
  });
}

class _CountedString {
  final String value;
  final int nextOffset;

  _CountedString(this.value, this.nextOffset);
}
