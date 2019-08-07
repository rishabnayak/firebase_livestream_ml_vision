#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'firebase_livestream_ml_vision'
  s.version          = '0.0.1'
  s.summary          = 'Flutter plugin for Firebase MLVision with Live Camera'
  s.description      = <<-DESC
Flutter plugin for Firebase MLVision with Live Camera
                       DESC
  s.homepage         = 'https://github.com/rishab2113/firebase_livestream_ml_vision/tree/master'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Rishab Nayak' => 'rishab@bu.edu' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.dependency 'Firebase/Core'
  s.dependency 'Firebase/MLCommon'
  s.dependency 'Firebase/MLVision'
  s.dependency 'Firebase/MLVisionAutoML'
  s.ios.deployment_target = '9.0'
  s.static_framework = true
end

