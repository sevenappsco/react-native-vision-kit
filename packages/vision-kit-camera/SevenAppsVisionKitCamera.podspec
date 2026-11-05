require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name         = 'SevenAppsVisionKitCamera'
  s.version      = package['version']
  s.summary      = package['description']
  s.homepage     = package['repository']
  s.license      = package['license']
  s.authors      = package['author']

  s.platforms    = { :ios => '16.4' }
  s.source       = { :git => package['repository'], :tag => "#{s.version}" }

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
