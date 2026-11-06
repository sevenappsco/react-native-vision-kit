require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))
# npm/pnpm pack normalize "repository" to { type, url }; the source tree has a plain string.
repository = package['repository'].is_a?(Hash) ? package['repository']['url'] : package['repository']

Pod::Spec.new do |s|
  s.name         = 'SevenAppsVisionKitCamera'
  s.version      = package['version']
  s.summary      = package['description']
  s.homepage     = repository
  s.license      = package['license']
  s.authors      = package['author']

  s.platforms    = { :ios => '16.4' }
  s.source       = { :git => repository, :tag => "#{s.version}" }

  s.source_files = [
    'ios/**/*.{swift}',
    'ios/**/*.{m,mm}',
  ]
  # Apple frameworks only. No Google ML Kit on iOS.
  s.frameworks = ['AVFoundation', 'Vision']

  load 'nitrogen/generated/ios/SevenAppsVisionKitCamera+autolinking.rb'
  add_nitrogen_files(s)

  s.dependency 'React-jsi'
  s.dependency 'React-callinvoker'
  s.dependency 'VisionCamera'
  install_modules_dependencies(s)
end
