Pod::Spec.new do |s|
  s.name             = 'flutter_face_nova'
  s.version          = '1.0.0'
  s.summary          = 'Offline, on-device face liveness and identity verification SDK'
  s.description      = 'Offline, on-device Flutter SDK for face liveness detection and identity verification. No server required.'
  s.homepage         = 'https://github.com/facenova/flutter_face_nova'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'FaceNova' => 'support@facenova.uk' }
  s.source           = { :path => '.' }
  s.vendored_frameworks = 'Frameworks/BinimiseBiometric.xcframework'
  s.dependency 'Flutter'
  s.platform         = :ios, '14.0'
end
