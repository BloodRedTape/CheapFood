class ScrapeRequest {
  final String url;
  final int timeout;
  final bool downloadMedia;

  /// BCP-47 language tag for translation (e.g. 'en', 'ru', 'cs').
  /// If null, items are returned in their original language.
  final String? language;

  const ScrapeRequest({
    required this.url,
    this.timeout = 30,
    this.downloadMedia = true,
    this.language,
  });

  Map<String, dynamic> toJson() => {
        'url': url,
        'timeout': timeout,
        'download_media': downloadMedia,
        if (language != null) 'language': language,
      };
}
