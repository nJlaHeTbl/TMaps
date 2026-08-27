{{flutter_js}}
{{flutter_build_config}}

// Version the application entry point while keeping the public URL stable.
const tmapsBuildVersion = {{flutter_service_worker_version}};
for (const build of _flutter.buildConfig.builds) {
  if (build.mainJsPath) {
    build.mainJsPath = `${build.mainJsPath}?v=${tmapsBuildVersion}`;
  }
}

// TMaps is an online map. Retire a legacy worker before loading application
// code so an installed PWA cannot start with a previous main.dart.js.
Promise.resolve(window.tmapsPrepareForLatestBuild).then((shouldLoad) => {
  if (shouldLoad !== false) {
    _flutter.loader.load();
  }
});
