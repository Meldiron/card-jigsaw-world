# Adds a temporary UI test target (RunnerUITests) and its scheme to ios/Runner.xcodeproj for
# tools/dev/notification_check.sh, which restores the project afterwards. Never commit the result:
# the CI archive and `flutter build ios` only know the Runner scheme. Uses the xcodeproj gem that
# ships with CocoaPods.
require 'xcodeproj'

proj_path = ARGV.fetch(0)
project = Xcodeproj::Project.open(proj_path)
abort 'RunnerUITests is already in the project' if project.targets.any? { |t| t.name == 'RunnerUITests' }
app = project.targets.find { |t| t.name == 'Runner' }

target = project.new_target(:ui_test_bundle, 'RunnerUITests', :ios, '16.4')
group = project.main_group.new_group('RunnerUITests', 'RunnerUITests')
target.add_file_references([group.new_reference('GiftNotificationUITests.swift')])
target.add_dependency(app)
target.build_configurations.each do |c|
  c.build_settings.merge!(
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.matejbaco.cardjigsawworld.RunnerUITests',
    'TEST_TARGET_NAME' => 'Runner',
    'DEVELOPMENT_TEAM' => 'C24QP73SQM',
    'CODE_SIGN_STYLE' => 'Automatic',
    'SWIFT_VERSION' => '5.0',
    'IPHONEOS_DEPLOYMENT_TARGET' => '16.4',
    'GENERATE_INFOPLIST_FILE' => 'YES',
    'SDKROOT' => 'iphoneos',
    'TARGETED_DEVICE_FAMILY' => '1',
  )
end
project.save

# The scheme is the Runner scheme (its "Prepare Flutter Framework" pre-action builds the Flutter
# framework the Swift packages need) with this target as its only test.
schemes = File.join(proj_path, 'xcshareddata', 'xcschemes')
runner = File.read(File.join(schemes, 'Runner.xcscheme'))
testables = <<~XML.strip
  <Testables>
           <TestableReference
              skipped = "NO">
              <BuildableReference
                 BuildableIdentifier = "primary"
                 BlueprintIdentifier = "#{target.uuid}"
                 BuildableName = "RunnerUITests.xctest"
                 BlueprintName = "RunnerUITests"
                 ReferencedContainer = "container:Runner.xcodeproj">
              </BuildableReference>
           </TestableReference>
        </Testables>
XML
File.write(File.join(schemes, 'RunnerUITests.xcscheme'), runner.sub(%r{<Testables>.*?</Testables>}m, testables))
puts 'added RunnerUITests (temporary)'
