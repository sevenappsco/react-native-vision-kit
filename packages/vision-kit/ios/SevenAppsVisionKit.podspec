require 'json'

package = JSON.parse(File.read(File.join(__dir__, '..', 'package.json')))
# npm/pnpm pack normalize "repository" to { type, url }; the source tree has a plain string.
repository = package['repository'].is_a?(Hash) ? package['repository']['url'] : package['repository']

Pod::Spec.new do |s|
  s.name           = 'SevenAppsVisionKit'
  s.module_name    = 'SevenAppsVisionKit'
  s.version        = package['version']
  s.summary        = package['description']
  s.description    = package['description']
  s.license        = package['license']
  s.author         = package['author']
  s.homepage       = repository
  s.platforms      = { :ios => '16.4' }
  s.swift_version  = '5.9'
  s.source         = { git: repository }
  s.static_framework = true

  s.dependency 'ExpoModulesCore'
  # Apple frameworks only. No Google ML Kit on iOS.
  s.frameworks = 'Vision', 'ImageIO', 'CoreImage', 'SwiftUI'
  s.weak_frameworks = 'Translation'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
  }

  s.source_files = "**/*.{h,m,mm,swift}"
end
