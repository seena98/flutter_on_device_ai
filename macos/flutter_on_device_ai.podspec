Pod::Spec.new do |s|
  s.name             = 'flutter_on_device_ai'
  s.version          = '0.1.0'
  s.summary          = 'On-device generative AI for Flutter using the models the OS already ships.'
  s.description      = <<-DESC
Apple Foundation Models on macOS, with sessions, streaming, tool calling, structured output
and a pluggable fallback engine.
                       DESC
  s.homepage         = 'https://github.com/seena98/flutter_on_device_ai'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Seena' => 'sinaashrafpour@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.15'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
  s.weak_frameworks = 'FoundationModels'
  s.resource_bundles = { 'flutter_on_device_ai_privacy' => ['Resources/PrivacyInfo.xcprivacy'] }
end
