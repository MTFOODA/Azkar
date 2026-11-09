Pod::Spec.new do |s|
  s.name = 'azkar_mobile'
  s.version = '1.0.0'
  s.summary = 'Native AZKAR widget bridge.'
  s.description = 'Registers the AZKAR widget bridge in foreground and background Flutter engines.'
  s.homepage = 'https://github.com/MTFOODA/Azkar'
  s.license = { :type => 'MIT' }
  s.author = { 'AZKAR' => 'azkar@example.invalid' }
  s.source = { :path => '.' }
  s.source_files = 'azkar_mobile/Sources/azkar_mobile/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.swift_version = '5.0'
end
