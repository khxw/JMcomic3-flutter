const githubDownloadMirrorPrefixes = <String>[
  'https://gh-proxy.org/',
  'https://ghfast.top/',
  'https://gh-proxy.com/',
];

List<String> githubDownloadCandidates(
  Iterable<String> officialUrls, {
  bool includeMirrors = true,
}) {
  final official = <String>[];
  for (final rawUrl in officialUrls) {
    final url = stripGitHubMirrorPrefix(rawUrl.trim());
    if (url.isEmpty || official.contains(url)) continue;
    official.add(url);
  }
  final result = <String>[];
  if (includeMirrors) {
    for (final prefix in githubDownloadMirrorPrefixes) {
      for (final url in official) {
        if (isGitHubDownloadUrl(url)) {
          result.add('$prefix$url');
        }
      }
    }
  }
  result.addAll(official);
  return List.unmodifiable(result.toSet());
}

String stripGitHubMirrorPrefix(String url) {
  for (final prefix in githubDownloadMirrorPrefixes) {
    if (url.startsWith(prefix)) return url.substring(prefix.length);
  }
  return url;
}

bool isGitHubDownloadUrl(String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  return host == 'github.com' ||
      host == 'raw.githubusercontent.com' ||
      host == 'api.github.com';
}
