class AppConfig {
  // GitHub repository URL - update this with your actual repository
  static const String githubRepositoryUrl =
      'https://github.com/richee-bot/rtwrt-app';

  /// Owner/name used by the phone app release.
  static const String githubRepo = 'richee-bot/rtwrt-app';

  /// Sysupgrade images are published on this repo.
  static const String firmwareRepo = 'richee-bot/rtwrt-aw1000-firmware';

  /// rpcd ACL the phone installs so ubus can run the router tools.
  static const String connectorUrl =
      'https://raw.githubusercontent.com/richee-bot/rtwrt-app/main/connector/luci-app-rtwrt.json';

  // GitHub issues URL
  static const String githubIssuesUrl = '$githubRepositoryUrl/issues';

  // Reviewer mode configuration
  static const String reviewerModeKey = 'reviewer_mode_enabled';
  static const String mockDataPath = 'assets/mock/';
  static const Duration reviewerModeActivationDuration = Duration(seconds: 5);
  static const String reviewerModeWatermark = 'Reviewer Mode';
}
