# Fügt dem Runner-Projekt die Widget-Erweiterung „CoachWidgets“ hinzu (Homescreen-Widgets und Live-Aktivitäten,
# SwiftUI). Einmalig ausgeführt, Ergebnis eingecheckt; erneutes Ausführen ändert nichts. Ohne Mac: läuft mit dem
# Ruby-Gem `xcodeproj` auch unter Linux (`gem install xcodeproj`, dann `ruby ios/scripts/add_widget_extension.rb`).
require 'xcodeproj'

ROOT = File.expand_path('..', __dir__)
project = Xcodeproj::Project.open(File.join(ROOT, 'Runner.xcodeproj'))
NAME = 'CoachWidgets'

if project.targets.any? { |target| target.name == NAME }
  puts "#{NAME} ist schon vorhanden."
  exit 0
end

runner = project.targets.find { |target| target.name == 'Runner' }
widgets = project.new_target(:app_extension, NAME, :ios, '18.0', nil, :swift)

# Gruppen und Dateien: CoachWidgets nur in der Erweiterung, Shared in App und Erweiterung (Live-Aktivitäten: die
# Intents der Knöpfe laufen im Prozess der App).
widget_group = project.main_group.new_group(NAME, NAME)
shared_group = project.main_group.new_group('Shared', 'Shared')
Dir.glob(File.join(ROOT, NAME, '*.swift')).sort.each do |path|
  widgets.source_build_phase.add_file_reference(widget_group.new_file(File.basename(path)))
end
%w[Info.plist CoachWidgets.entitlements].each { |name| widget_group.new_file(name) }
Dir.glob(File.join(ROOT, 'Shared', '*.swift')).sort.each do |path|
  ref = shared_group.new_file(File.basename(path))
  widgets.source_build_phase.add_file_reference(ref)
  runner.source_build_phase.add_file_reference(ref)
end

%w[WidgetKit SwiftUI ActivityKit AppIntents].each do |framework|
  widgets.frameworks_build_phase.add_file_reference(project.frameworks_group.new_file("System/Library/Frameworks/#{framework}.framework", :sdk_root))
end

# Versionsnummern wie die App (FLUTTER_BUILD_NAME/NUMBER aus Generated.xcconfig).
generated = project.files.find { |file| file.path == 'Flutter/Generated.xcconfig' }
widgets.build_configurations.each do |config|
  config.base_configuration_reference = generated
  settings = config.build_settings
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'io.github.hkrb7p794w.coach.widgets'
  settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  settings['INFOPLIST_FILE'] = "#{NAME}/Info.plist"
  settings['CODE_SIGN_ENTITLEMENTS'] = "#{NAME}/#{NAME}.entitlements"
  settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  settings['IPHONEOS_DEPLOYMENT_TARGET'] = '18.0'
  settings['TARGETED_DEVICE_FAMILY'] = '1'
  settings['SWIFT_VERSION'] = '6.0'
  # Ohne MainActor-Voreinstellung: `@Parameter` in Konfigurations-Intents geht sonst nicht (wie in der Swift-App).
  settings['SWIFT_DEFAULT_ACTOR_ISOLATION'] = 'nonisolated'
  settings['SWIFT_APPROACHABLE_CONCURRENCY'] = 'YES'
  settings['SKIP_INSTALL'] = 'YES'
  settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  settings['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
  settings['CURRENT_PROJECT_VERSION'] = '$(FLUTTER_BUILD_NUMBER)'
  settings['MARKETING_VERSION'] = '$(FLUTTER_BUILD_NAME)'
  settings['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = 'AccentColor'
  settings['CODE_SIGN_STYLE'] = 'Automatic'
  settings.delete('ASSETCATALOG_COMPILER_APPICON_NAME')
end

# In die App einbetten (PlugIns). Vor den Skript-Phasen von Flutter, sonst meldet Xcode einen Zyklus
# („Cycle inside Runner“ mit „Thin Binary“).
runner.add_dependency(widgets)
embed = runner.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
embed.add_file_reference(widgets.product_reference).settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
runner.build_phases.delete(embed)
index = runner.build_phases.index { |phase| phase.is_a?(Xcodeproj::Project::Object::PBXShellScriptBuildPhase) && phase.name == 'Thin Binary' } ||
        runner.build_phases.index(runner.resources_build_phase) + 1
runner.build_phases.insert(index, embed)

project.save
puts "#{NAME} hinzugefügt."
