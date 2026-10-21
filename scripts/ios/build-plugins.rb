#!/usr/bin/env ruby
# Build every exported uni_modules/*/utssdk/app-ios plugin into a device xcframework.
# Requires: gem install xcodeproj, Xcode.
require 'xcodeproj'
require 'json'
require 'fileutils'
require 'open3'
require 'shellwords'

SDK_ROOT = ENV.fetch('SDK_ROOT')
PLUGINS_ROOT = ENV.fetch('PLUGINS_ROOT')
PLUGIN_OUT = ENV.fetch('PLUGIN_OUT')
PLUGIN_BUILD = ENV.fetch('PLUGIN_BUILD')
LOGS = ENV.fetch('LOGS', PLUGIN_BUILD)

FileUtils.mkdir_p(PLUGIN_OUT)
FileUtils.mkdir_p(PLUGIN_BUILD)

SDK_LIBS = File.join(SDK_ROOT, 'SDK', 'libs')
EXT_SRC = File.join(SDK_ROOT, 'SDK', 'ExtApiSrc')
EXT_API = File.join(SDK_ROOT, 'TemporarySampleFramework', 'DCloudUTSExtAPI.xcframework')
abort "missing SDK libs: #{SDK_LIBS}" unless Dir.exist?(SDK_LIBS)
abort "missing DCloudUTSExtAPI: #{EXT_API}" unless Dir.exist?(EXT_API)

def camel(name)
  name.split(/[-_]/).map { |part| part.empty? ? part : part[0].upcase + part[1..] }.join
end

def sh!(cmd, log_path)
  puts cmd
  output, status = Open3.capture2e(cmd)
  File.open(log_path, 'a') { |f| f.puts "\n$ #{cmd}\n#{output}" }
  abort("command failed (#{status.exitstatus}): #{cmd}\n#{output[-4000..] || output}") unless status.success?
  output
end

def add_link(project, target, path)
  ref = project.frameworks_group.new_file(path)
  target.frameworks_build_phase.add_file_reference(ref)
  ref
end

plugins = Dir.glob(File.join(PLUGINS_ROOT, '*')).sort
abort "no plugins under #{PLUGINS_ROOT}" if plugins.empty?

built = []
plugins.each do |plugin_dir|
  ios_dir = File.join(plugin_dir, 'utssdk', 'app-ios')
  swift_sources = Dir.glob(File.join(ios_dir, 'src', '**', '*.swift')).sort
  next if swift_sources.empty?

  plugin = File.basename(plugin_dir)
  target_name = "unimodule#{camel(plugin)}"
  proj_dir = File.join(PLUGIN_BUILD, target_name)
  FileUtils.rm_rf(proj_dir)
  FileUtils.mkdir_p(proj_dir)
  log = File.join(LOGS, "plugin-#{plugin}.log")
  FileUtils.rm_f(log)

  config_path = File.join(ios_dir, 'config.json')
  config = File.exist?(config_path) ? JSON.parse(File.read(config_path)) : {}

  puts "\n=== #{plugin} -> #{target_name} ==="
  project = Xcodeproj::Project.new(File.join(proj_dir, "#{target_name}.xcodeproj"))
  target = project.new_target(:framework, target_name, :ios, '15.0')
  group = project.main_group.new_group('Sources', ios_dir)

  sources = swift_sources + [
    File.join(EXT_SRC, 'UTSOC.mm'),
    File.join(EXT_SRC, 'UTSCPP.mm')
  ]
  sources.each do |file|
    ref = group.new_file(file)
    target.add_file_references([ref])
  end
  %w[UTSOC.h UTSCPP.h].each do |header|
    group.new_file(File.join(EXT_SRC, header))
  end

  # UTSOC.mm's DCloudUTSConfig reads uts-config.json from the framework bundle.
  uts_config = {}
  uts_config['hooksClasses'] = [config['hooksClass']] if config['hooksClass']
  uts_config['providers'] = config['providers'] if config['providers']
  uts_config['components'] = config['components'] if config['components']
  effective_config = File.join(proj_dir, 'uts-config.json')
  File.write(effective_config, JSON.pretty_generate(uts_config))
  cfg_ref = group.new_file(effective_config)
  target.resources_build_phase.add_file_reference(cfg_ref)

  framework_dir = File.join(ios_dir, 'Frameworks')
  if Dir.exist?(framework_dir)
    Dir.glob(File.join(framework_dir, '*')).sort.each do |framework|
      add_link(project, target, framework)
    end
  end

  lib_dir = File.join(ios_dir, 'Libs')
  if Dir.exist?(lib_dir)
    Dir.glob(File.join(lib_dir, '*.a')).sort.each do |library|
      add_link(project, target, library)
    end
  end

  [
    File.join(SDK_LIBS, 'DCloudUniappRuntime.xcframework'),
    File.join(SDK_LIBS, 'DCloudUTSFoundation.xcframework')
  ].each { |framework| add_link(project, target, framework) }

  system_frameworks = Array(config['frameworks']).map { |f| f.sub(/\.framework\z/, '') }
  system_libs = Array(config['libs'])
  ldflags = ['-ObjC'] + system_frameworks.map { |f| "-framework #{f}" } + system_libs.map { |l| "-l#{l}" }

  target.build_configurations.each do |build_config|
    s = build_config.build_settings
    s['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
    s['MACH_O_TYPE'] = 'mh_dylib'
    s['DEFINES_MODULE'] = 'YES'
    s['GENERATE_INFOPLIST_FILE'] = 'YES'
    s['PRODUCT_BUNDLE_IDENTIFIER'] = "com.zhaiwo.plugin.#{target_name.downcase}"
    s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@loader_path/Frameworks']
    s['BUILD_LIBRARY_FOR_DISTRIBUTION'] = 'YES'
    s['ENABLE_MODULE_VERIFIER'] = 'NO'
    s['CLANG_ENABLE_MODULES'] = 'YES'
    s['CLANG_ENABLE_OBJC_ARC'] = 'YES'
    s['CLANG_CXX_LANGUAGE_STANDARD'] = 'gnu++20'
    s['SWIFT_VERSION'] = '5.0'
    s['SWIFT_INSTALL_OBJC_HEADER'] = 'YES'
    s['SKIP_INSTALL'] = 'NO'
    s['OTHER_LDFLAGS'] = ldflags
    s['FRAMEWORK_SEARCH_PATHS'] = [SDK_LIBS, framework_dir].select { |p| Dir.exist?(p) }
    s['LIBRARY_SEARCH_PATHS'] = [lib_dir, SDK_LIBS].select { |p| Dir.exist?(p) }
    s['CODE_SIGNING_ALLOWED'] = 'NO'
    s['CODE_SIGNING_REQUIRED'] = 'NO'
  end

  project.save

  pods = Array(config['dependencies-pods'])
  workspace = nil
  unless pods.empty?
    podfile = <<~PODFILE
      platform :ios, '15.0'
      target '#{target_name}' do
        use_frameworks! :linkage => :static
        #{pods.map { |p| "pod '#{p['name']}', '#{p['version']}'" }.join("\n  ")}
      end
    PODFILE
    File.write(File.join(proj_dir, 'Podfile'), podfile)
    sh!("cd #{proj_dir.shellescape} && pod install --repo-update", log)
    workspace = File.join(proj_dir, "#{target_name}.xcworkspace")
  end

  project_arg = workspace ? "-workspace #{workspace.shellescape}" : "-project #{File.join(proj_dir, "#{target_name}.xcodeproj").shellescape}"
  dd = File.join(proj_dir, 'DerivedData')
  sh!(
    "xcodebuild #{project_arg} -scheme #{target_name} -configuration Release -sdk iphoneos " \
    "-arch arm64 -derivedDataPath #{dd.shellescape} CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO " \
    "BUILD_LIBRARY_FOR_DISTRIBUTION=YES build",
    log
  )

  framework_product = File.join(dd, 'Build', 'Products', 'Release-iphoneos', "#{target_name}.framework")
  abort "missing built framework: #{framework_product}" unless Dir.exist?(framework_product)

  out_framework = File.join(PLUGIN_OUT, "#{target_name}.xcframework")
  FileUtils.rm_rf(out_framework)
  sh!("xcodebuild -create-xcframework -framework #{framework_product.shellescape} -output #{out_framework.shellescape}", log)
  built << { plugin: plugin, target: target_name, framework: out_framework }
end

File.write(File.join(PLUGIN_OUT, 'manifest.json'), JSON.pretty_generate(built))
puts "\nbuilt #{built.length} plugin frameworks:"
built.each { |item| puts "  #{item[:plugin]} -> #{File.basename(item[:framework])}" }
