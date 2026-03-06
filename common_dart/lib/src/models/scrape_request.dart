class ScrapeRequest {
  final String url;
  final int timeout;
  final bool downloadMedia;

  const ScrapeRequest({
    required this.url,
    this.timeout = 30,
    this.downloadMedia = true,
  });

  Map<String, dynamic> toJson() => {
        'url': url,
        'timeout': timeout,
        'download_media': downloadMedia,
      };
}
