class SupabaseConfig {
  static const String url = 'https://lrjgocjubpxruobshtoe.supabase.co';
  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxyamdvY2p1YnB4cnVvYnNodG9lIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMyNTQwMTUsImV4cCI6MjA4ODgzMDAxNX0.hQrCDgMdhJ_B2ncjNhDBFetnnxhpbt7vP-EnzgKFT_I';

  static Uri functionUri(String name) {
    return Uri.parse('$url/functions/v1/$name');
  }
}
