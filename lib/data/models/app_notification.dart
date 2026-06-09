class AppVersionInfo {
  const AppVersionInfo({
    required this.latestVersion,
    required this.latestBuild,
    required this.minBuild,
    required this.apkUrl,
    required this.notes,
    required this.updateAvailable,
    required this.forceUpdate,
  });

  final String latestVersion;
  final int latestBuild;
  final int minBuild;
  final String apkUrl;
  final String notes;
  final bool updateAvailable;
  final bool forceUpdate;

  factory AppVersionInfo.fromJson(Map<String, dynamic> json) {
    return AppVersionInfo(
      latestVersion: json['latestVersion']?.toString() ?? '',
      latestBuild: int.tryParse(json['latestBuild']?.toString() ?? '') ?? 0,
      minBuild: int.tryParse(json['minBuild']?.toString() ?? '') ?? 0,
      apkUrl: (json['downloadUrl'] ??
              json['apkUrl'] ??
              json['ipaUrl'] ??
              json['windowsUrl'] ??
              json['zipUrl'] ??
              json['url'])
          ?.toString() ??
          '',
      notes: json['notes']?.toString() ?? '',
      updateAvailable: json['updateAvailable'] == true,
      forceUpdate: json['forceUpdate'] == true,
    );
  }
}
