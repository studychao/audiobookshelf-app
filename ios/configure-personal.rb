require 'xcodeproj'
require 'fileutils'

root = File.expand_path('App', __dir__)
project = Xcodeproj::Project.open(File.join(root, 'App.xcodeproj'))
host = project.targets.find { |target| target.name == 'Audiobookshelf' }
raise 'Audiobookshelf target not found' unless host
group_id = 'group.com.chaowu.audiobookshelf'
carplay = ARGV.include?('--carplay')
core = ARGV.include?('--core')
raise 'CarPlay and core-only modes cannot be combined' if carplay && core
personal = project.main_group.find_subpath('Personal', true)
personal.set_source_tree('<group>')
personal.path = 'Personal'

def add_source(project, group, target, path)
  reference = group.files.find { |file| file.path == path } || group.new_file(path)
  target.source_build_phase.add_file_reference(reference) unless target.source_build_phase.files_references.include?(reference)
end

%w[PersonalShared.swift AbsPersonal.swift ListeningShortcuts.swift CarPlaySceneDelegate.swift PhoneSceneDelegate.swift].each { |path| add_source(project, personal, host, path) }
%w[DownloadValidation.swift ProgressSyncPolicy.swift].each do |name|
  path = "Shared/player/util/#{name}"
  add_source(project, project.main_group, host, path)
end

entitlements = { 'com.apple.security.application-groups' => [group_id] }
Xcodeproj::Plist.write_to_path(entitlements, File.join(root, 'Personal', 'Personal.entitlements'))
Xcodeproj::Plist.write_to_path(entitlements.merge('com.apple.developer.carplay-audio' => true), File.join(root, 'Personal', 'CarPlay.entitlements'))
host.build_configurations.each { |config| config.build_settings['CODE_SIGN_ENTITLEMENTS'] = core ? '' : (carplay ? 'Personal/CarPlay.entitlements' : 'Personal/Personal.entitlements') }
project.root_object.attributes['TargetAttributes'] ||= {}
attributes = project.root_object.attributes['TargetAttributes'][host.uuid] ||= {}
attributes['SystemCapabilities'] ||= {}
attributes['SystemCapabilities']['com.apple.ApplicationGroups.iOS'] = { 'enabled' => core ? 0 : 1 }

base_info = { 'CFBundleDevelopmentRegion' => 'zh_CN', 'CFBundleExecutable' => '$(EXECUTABLE_NAME)', 'CFBundleIdentifier' => '$(PRODUCT_BUNDLE_IDENTIFIER)', 'CFBundleInfoDictionaryVersion' => '6.0', 'CFBundleName' => '$(PRODUCT_NAME)', 'CFBundlePackageType' => 'XPC!', 'CFBundleShortVersionString' => '$(MARKETING_VERSION)', 'CFBundleVersion' => '$(CURRENT_PROJECT_VERSION)' }
extensions = [
  ['AudiobookshelfShare', 'share', '15.0', ['PersonalShared.swift', 'ShareViewController.swift'], { 'NSExtensionPointIdentifier' => 'com.apple.share-services', 'NSExtensionPrincipalClass' => '$(PRODUCT_MODULE_NAME).ShareViewController', 'NSExtensionAttributes' => { 'NSExtensionActivationRule' => { 'NSExtensionActivationSupportsFileWithMaxCount' => 1000, 'NSExtensionActivationSupportsAttachmentsWithMaxCount' => 1000 } } }],
  ['AudiobookshelfWidget', 'widget', '17.0', ['PersonalShared.swift', 'ContinueListeningWidget.swift'], { 'NSExtensionPointIdentifier' => 'com.apple.widgetkit-extension' }]
]
embed = host.copy_files_build_phases.find { |phase| phase.name == 'Embed Personal Extensions' } || host.new_copy_files_build_phase('Embed Personal Extensions')
embed.dst_subfolder_spec = '13'
extensions.each do |name, suffix, deployment, sources, extension_info|
  target = project.targets.find { |candidate| candidate.name == name } || project.new_target(:app_extension, name, :ios, deployment)
  target.build_configurations.each do |config|
    config.build_settings['PRODUCT_NAME'] = name
    config.build_settings['PRODUCT_MODULE_NAME'] = name
    config.build_settings['ENABLE_DEBUG_DYLIB'] = 'NO'
    config.build_settings.merge!('PRODUCT_BUNDLE_IDENTIFIER' => "com.chaowu.audiobookshelf.#{suffix}", 'DEVELOPMENT_TEAM' => '3F6GUF4Q64', 'CODE_SIGN_STYLE' => 'Automatic', 'CODE_SIGN_ENTITLEMENTS' => 'Personal/Personal.entitlements', 'INFOPLIST_FILE' => "Personal/#{name}-Info.plist", 'SWIFT_VERSION' => '5.0', 'TARGETED_DEVICE_FAMILY' => '1,2', 'MARKETING_VERSION' => host.build_configurations.first.build_settings['MARKETING_VERSION'] || '0.14.0', 'CURRENT_PROJECT_VERSION' => host.build_configurations.first.build_settings['CURRENT_PROJECT_VERSION'] || '1', 'APPLICATION_EXTENSION_API_ONLY' => 'YES', 'SKIP_INSTALL' => 'YES')
  end
  sources.each { |source| add_source(project, personal, target, source) }
  Xcodeproj::Plist.write_to_path(base_info.merge('CFBundleDisplayName' => suffix == 'share' ? '添加到 Audiobookshelf' : '继续听书', 'NSExtension' => extension_info), File.join(root, 'Personal', "#{name}-Info.plist"))
  if core
    host.dependencies.select { |dependency| dependency.target == target }.each(&:remove_from_project)
    embed.files.select { |file| file.file_ref == target.product_reference }.each(&:remove_from_project)
  else
    host.add_dependency(target) unless host.dependencies.any? { |dependency| dependency.target == target }
  end
  unless core || embed.files_references.include?(target.product_reference)
    build_file = embed.add_file_reference(target.product_reference)
    build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
  end
end

info_path = File.join(root, 'App', 'Info.plist')
info = Xcodeproj::Plist.read_from_path(info_path)
schemes = info['CFBundleURLTypes'].first['CFBundleURLSchemes']
schemes << 'chaoaudiobook' unless schemes.include?('chaoaudiobook')
info['LSSupportsOpeningDocumentsInPlace'] = true
info['PersonalAppGroupsEnabled'] = !core
info['CFBundleDocumentTypes'] = [{ 'CFBundleTypeName' => '有声书音频', 'LSHandlerRank' => 'Alternate', 'LSItemContentTypes' => ['public.audio'] }]
if carplay
  info['UIApplicationSceneManifest'] = {
    'UIApplicationSupportsMultipleScenes' => false,
    'UISceneConfigurations' => {
      'UIWindowSceneSessionRoleApplication' => [{ 'UISceneConfigurationName' => 'Phone', 'UISceneDelegateClassName' => '$(PRODUCT_MODULE_NAME).PhoneSceneDelegate', 'UISceneStoryboardFile' => 'Main' }],
      'CPTemplateApplicationSceneSessionRoleApplication' => [{ 'UISceneConfigurationName' => 'CarPlay', 'UISceneClassName' => 'CPTemplateApplicationScene', 'UISceneDelegateClassName' => '$(PRODUCT_MODULE_NAME).CarPlaySceneDelegate' }]
    }
  }
else
  info.delete('UIApplicationSceneManifest')
end
Xcodeproj::Plist.write_to_path(info, info_path)

test_target = project.targets.find { |target| target.name == 'AudiobookshelfUnitTests' }
if test_target
  path = 'AudiobookshelfUnitTests/PersonalReliabilityTests.swift'
  add_source(project, project.main_group, test_target, path)
end
project.save
puts 'Configured personal extensions and reliability tests'
