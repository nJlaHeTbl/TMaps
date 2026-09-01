abstract final class MapTilePolicy {
  static const streetUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  static const satelliteUrl =
      'https://services.arcgisonline.com/ArcGIS/rest/services/'
      'World_Imagery/MapServer/tile/{z}/{y}/{x}';
  static const satelliteFallbackUrl =
      'https://server.arcgisonline.com/ArcGIS/rest/services/'
      'World_Imagery/MapServer/tile/{z}/{y}/{x}';
  static const satelliteLabelsUrl =
      'https://services.arcgisonline.com/ArcGIS/rest/services/'
      'Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}';
  static const satelliteLabelsFallbackUrl =
      'https://server.arcgisonline.com/ArcGIS/rest/services/'
      'Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}';

  /// Taldykorgan and parts of Kazakhstan contain Esri placeholder tiles above
  /// level 17. Scaling the last real tile keeps close zoom useful and avoids
  /// displaying "Map data not yet available" as if the app had failed.
  static const satelliteMaxNativeZoom = 17;
  static const satelliteLabelsMaxNativeZoom = 18;

  /// Esri returns placeholder imagery around Taldykorgan above level 17.
  /// Allow one extra display level for a useful close view, but stop before
  /// the native tile is enlarged so far that streets become unreadable.
  static const double satelliteMaxDisplayZoom = 18;

  static const keepBuffer = 2;
  static const panBuffer = 1;
}
