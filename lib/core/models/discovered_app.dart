import 'package:flutter/foundation.dart';

/// Source from which an application was discovered on Windows.
enum AppDiscoverySource {
  startMenu,
  registry,
  packagedApp,
  historicalTracked,
  custom,
}

/// Representation of an installed or tracked Windows application.
@immutable
class DiscoveredApp {
  /// Unique stable identifier (e.g. canonical executable path, AUMID, or normalized name).
  final String id;

  /// Human-readable friendly display name (e.g. "Google Chrome", "Telegram Desktop").
  final String displayName;

  /// Full path to the executable file, if known and verified on disk.
  final String? executablePath;

  /// Executable filename (e.g. "chrome.exe", "Telegram.exe").
  final String? executableName;

  /// Optional icon file path on disk (.ico, .png, etc.).
  final String? iconPath;

  /// Publisher or developer name, if available (e.g. "Microsoft Corporation", "Google LLC").
  final String? publisher;

  /// The primary source where this application was discovered.
  final AppDiscoverySource source;

  /// Whether Balance has recorded historical usage sessions for this application.
  final bool isPreviouslyTracked;

  /// Optional installation directory path.
  final String? installLocation;

  const DiscoveredApp({
    required this.id,
    required this.displayName,
    this.executablePath,
    this.executableName,
    this.iconPath,
    this.publisher,
    this.source = AppDiscoverySource.startMenu,
    this.isPreviouslyTracked = false,
    this.installLocation,
  });

  bool get hasExecutablePath =>
      executablePath != null && executablePath!.trim().isNotEmpty;

  /// Returns a copy with updated fields (e.g. merging tracking status or metadata).
  DiscoveredApp copyWith({
    String? id,
    String? displayName,
    String? executablePath,
    String? executableName,
    String? iconPath,
    String? publisher,
    AppDiscoverySource? source,
    bool? isPreviouslyTracked,
    String? installLocation,
  }) {
    return DiscoveredApp(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      executablePath: executablePath ?? this.executablePath,
      executableName: executableName ?? this.executableName,
      iconPath: iconPath ?? this.iconPath,
      publisher: publisher ?? this.publisher,
      source: source ?? this.source,
      isPreviouslyTracked: isPreviouslyTracked ?? this.isPreviouslyTracked,
      installLocation: installLocation ?? this.installLocation,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DiscoveredApp &&
        other.id.toLowerCase() == id.toLowerCase();
  }

  @override
  int get hashCode => id.toLowerCase().hashCode;

  @override
  String toString() =>
      'DiscoveredApp(id: $id, displayName: $displayName, exe: $executableName, source: $source, tracked: $isPreviouslyTracked)';
}
