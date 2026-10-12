{{flutter_js}}
{{flutter_build_config}}

// The web app talks only to Appwrite (owner rule): CanvasKit is bundled with the
// build (flutter build web --no-web-resources-cdn) and the default font is
// served from our own site instead of fonts.gstatic.com. Fallback fonts for
// scripts the app never shows are not hosted; a request for one stays on our
// domain.
_flutter.loader.load({
  config: {
    fontFallbackBaseUrl: "fallback-fonts/",
  },
});
