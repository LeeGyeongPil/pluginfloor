Pod::Spec.new do |s|
  s.name             = 'snap_camera_darwin'
  s.version          = '1.2.0'
  s.summary          = 'Fake plugin for the pluginfloor sample.'
  s.source_files     = 'snap_camera_darwin/Sources/**/*'
  s.ios.deployment_target = '12.0'
  s.osx.deployment_target = '10.14'
end
