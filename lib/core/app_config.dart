abstract final class AppConfig {
  static const publicAppUrl = 'https://njlahetbl.github.io/TMaps/';

  /// Public contact channel named in the privacy policy and terms.
  static const contactUrl = 'https://github.com/nJlaHeTbl/TMaps/issues';

  static const supabaseUrl = 'https://fbvvaozvgledhiidvplw.supabase.co';
  static const supabasePublishableKey =
      'sb_publishable_DdevGM-RfKW0wdmFezhFhw_23oVq39Y';

  /// Optional community API used after the Cloudflare migration is deployed.
  /// Keeping it empty preserves the current Supabase backend on the live site.
  static const communityApiBaseUrl = String.fromEnvironment(
    'TMAPS_API_BASE_URL',
  );

  static bool get usesCommunityApi => communityApiBaseUrl.trim().isNotEmpty;

  static const routingBaseUrl =
      'https://routing.openstreetmap.de/routed-foot/route/v1/driving';
}
