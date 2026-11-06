#!/usr/bin/env bash
# Lints the podspecs exactly as consumers get them: from the packed tarball,
# not the workspace source. `pnpm pack` rewrites package.json (e.g. it turns
# "repository": "https://…" into { type, url }), which the workspace never sees.
set -euo pipefail
export LANG=en_US.UTF-8

root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

check() {
  local pkg="$1" podspec="$2"
  local dest="$work/$(basename "$pkg")"
  mkdir -p "$dest"
  (cd "$root/$pkg" && pnpm pack --pack-destination "$dest" >/dev/null)
  tar -xzf "$dest"/*.tgz -C "$dest"
  echo "==> $pkg: linting $podspec from the tarball"
  # CocoaPods' attribute linter (what `pod install` runs on every pod) without
  # resolving dependencies, so Nitro/VisionCamera/Expo pods aren't needed.
  (cd "$dest/package" && ruby -e '
    require "cocoapods"
    # Provided by react-native/scripts/react_native_pods.rb in a real app.
    def install_modules_dependencies(_spec); end
    linter = Pod::Specification::Linter.new(ARGV[0])
    linter.lint
    linter.results.each { |r| puts "    #{r}" }
    abort "    FAILED" if linter.results.any? { |r| r.type == :error }
    puts "    ok (#{linter.spec.name} #{linter.spec.version}, homepage=#{linter.spec.homepage})"
  ' "$podspec")
}

check packages/vision-kit ios/SevenAppsVisionKit.podspec
check packages/vision-kit-camera SevenAppsVisionKitCamera.podspec
echo "Packed podspecs OK"
