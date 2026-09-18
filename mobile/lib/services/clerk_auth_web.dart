// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

void launchUrlPlatform(String url) {
  html.window.location.href = url;
}

String getCurrentOrigin() {
  return html.window.location.origin;
}
