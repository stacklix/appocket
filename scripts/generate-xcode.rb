require 'xcodeproj'
root = File.expand_path('..', __dir__)
path = File.join(root, 'ios/Appocket.xcodeproj')
project = Xcodeproj::Project.new(path)
target = project.new_target(:application, 'Appocket', :ios, '17.0')
group = project.main_group.new_group('Appocket', 'Appocket')
Dir.glob(File.join(root, 'ios/Appocket/**/*.swift')).sort.each do |file|
  relative = file.delete_prefix(File.join(root, 'ios/Appocket/'))
  target.source_build_phase.add_file_reference(group.new_file(relative))
end
resources = group.new_group('Resources', 'Resources')
%w[HostConfig.json BuiltinModules].each do |name|
  ref = resources.new_file(name)
  ref.last_known_file_type = 'folder' if name == 'BuiltinModules'
  target.resources_build_phase.add_file_reference(ref)
end
target.build_configurations.each do |config|
  config.build_settings.merge!({
    'PRODUCT_BUNDLE_IDENTIFIER' => 'me.stackli.appocket', 'SWIFT_VERSION' => '5.0',
    'INFOPLIST_KEY_CFBundleDisplayName' => 'Lingrove', 'INFOPLIST_KEY_CFBundleName' => 'Lingrove',
    'GENERATE_INFOPLIST_FILE' => 'YES', 'INFOPLIST_KEY_UILaunchScreen_Generation' => 'YES',
    'INFOPLIST_KEY_UIApplicationSceneManifest_Generation' => 'YES',
    'INFOPLIST_KEY_UISupportedInterfaceOrientations' => 'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight',
    'INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad' => 'UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight',
    'TARGETED_DEVICE_FAMILY' => '1,2', 'MARKETING_VERSION' => '1.0.0', 'CURRENT_PROJECT_VERSION' => '1',
    'CODE_SIGN_STYLE' => 'Automatic', 'ENABLE_USER_SCRIPT_SANDBOXING' => 'YES'
  })
end
ui = project.new_target(:ui_test_bundle, 'AppocketUITests', :ios, '17.0')
ui.add_dependency(target)
tests = project.main_group.new_group('UITests', 'UITests')
ui.source_build_phase.add_file_reference(tests.new_file('AppocketUITests.swift'))
ui.build_configurations.each do |config|
  config.build_settings.merge!({'SWIFT_VERSION'=>'5.0','GENERATE_INFOPLIST_FILE'=>'YES','PRODUCT_BUNDLE_IDENTIFIER'=>'me.stackli.appocket.uitests','TEST_TARGET_NAME'=>'Appocket','CODE_SIGN_STYLE'=>'Automatic'})
end
unit = project.new_target(:unit_test_bundle, 'AppocketRuntimeTests', :ios, '17.0')
unit.add_dependency(target)
runtime_tests = project.main_group.new_group('RuntimeTests', 'RuntimeTests')
unit.source_build_phase.add_file_reference(runtime_tests.new_file('RuntimeTests.swift'))
unit.build_configurations.each do |config|
  config.build_settings.merge!({'SWIFT_VERSION'=>'5.0','GENERATE_INFOPLIST_FILE'=>'YES','PRODUCT_BUNDLE_IDENTIFIER'=>'me.stackli.appocket.runtime-tests','TEST_HOST'=>'$(BUILT_PRODUCTS_DIR)/Appocket.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Appocket','BUNDLE_LOADER'=>'$(TEST_HOST)','CODE_SIGN_STYLE'=>'Automatic'})
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target)
scheme.add_test_target(ui)
scheme.add_test_target(unit)
scheme.set_launch_target(target)
scheme.save_as(path, 'Appocket', true)
puts path
