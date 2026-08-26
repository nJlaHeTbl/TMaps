{{flutter_js}}
{{flutter_build_config}}

// Version the application entry point while keeping the public URL stable.
const tmapsBuildVersion = {{flutter_service_worker_version}};
for (const build of _flutter.buildConfig.builds) {
  if (build.mainJsPath) {
    build.mainJsPath = `${build.mainJsPath}?v=${tmapsBuildVersion}`;
  }
}

// TMaps is an online map. Avoid a service worker pinning an outdated release.
_flutter.loader.load();
