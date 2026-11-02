#!/usr/bin/env ruby
# Configure the DCloud UniAppXVaporDemo host project for the app's App Store build.
require 'xcodeproj'
require 'fileutils'

project_path, plugin_out, plugins_root, info_plist, bundle_id, team_id, profile_name, version_name, version_code, add_plugins, entitlements = ARGV
abort 'usage: configure-host.rb <project> <plugin_out> <plugins_root> <info_plist> <bundle_id> <team_id> <profile> <version_name> <version_code> <add_plugins>' unless project_path

project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| ['UniAppX', 'UniAppXVaporDemo'].include?(t.name) } || project.targets.first
abort "target not found in #{project_path}" unless target

old_name = target.name
target.name = 'UniAppX'
schemes_dir = File.join(project_path, 'xcshareddata', 'xcschemes')
Dir.glob(File.join(schemes_dir, '*.xcscheme')).each do |scheme|
  contents = File.read(scheme)
  contents = contents.gsub(%(BlueprintName="#{old_name}"), %(BlueprintName="UniAppX"))
  contents = contents.gsub(%(BuildableName="#{old_name}.app"), %(BuildableName="UniAppX.app"))
  target_path = File.join(schemes_dir, 'UniAppX.xcscheme')
  File.write(target_path, contents)
  FileUtils.rm_f(scheme) unless scheme == target_path
end
puts "debug host target: #{target.name}"

target.build_configurations.each do |config|
  settings = config.build_settings
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = bundle_id
  settings['DEVELOPMENT_TEAM'] = team_id
  settings['CODE_SIGN_STYLE'] = 'Manual'
  settings['PROVISIONING_PROFILE_SPECIFIER'] = profile_name
  settings['CODE_SIGN_IDENTITY'] = 'Apple Development'
  settings['PRODUCT_NAME'] = 'UniAppX'
  settings['MARKETING_VERSION'] = version_name
  settings['CURRENT_PROJECT_VERSION'] = version_code
  settings['TARGETED_DEVICE_FAMILY'] = '1'
  settings['ENABLE_BITCODE'] = 'NO'
  settings['INFOPLIST_FILE'] = 'UniAppXVaporDemo/Info.plist'
  settings['CODE_SIGN_ENTITLEMENTS'] = entitlements if entitlements && !entitlements.empty?
  settings['GENERATE_INFOPLIST_FILE'] = 'YES'
end

# The debug base retains DCloudDebugServe for HBuilderX hot reload.
%w[unimoduleTesIosNotification.framework].each do |demo_name|
  demo_ref = project.files.find { |f| File.basename(f.path.to_s) == demo_name }
  next unless demo_ref

  target.frameworks_build_phase.files.select { |bf| bf.file_ref == demo_ref }.each(&:remove_from_project)
  target.copy_files_build_phases.each do |phase|
    phase.files.select { |bf| bf.file_ref == demo_ref }.each(&:remove_from_project)
  end
  demo_ref.remove_from_project
  puts "removed #{demo_name}"
end

if add_plugins == 'true' && plugin_out && File.directory?(plugin_out)
  embed = target.copy_files_build_phases.find { |p| p.name == 'Embed Frameworks' }
  unless embed
    embed = target.new_copy_files_build_phase('Embed Frameworks')
    embed.dst_subfolder_spec = '10'
  end

  Dir.glob(File.join(plugin_out, '*.xcframework')).sort.each do |framework|
    name = File.basename(framework)
    existing = project.files.find { |f| File.basename(f.path.to_s) == name }
    next if existing && target.frameworks_build_phase.files.any? { |bf| bf.file_ref == existing }

    ref = existing || project.frameworks_group.new_file(framework)
    target.frameworks_build_phase.add_file_reference(ref)
    build_file = embed.add_file_reference(ref)
    build_file.settings = { 'ATTRIBUTES' => %w[CodeSignOnCopy RemoveHeadersOnCopy] }
    puts "added plugin framework: #{name}"
  end
end

if plugins_root && File.directory?(plugins_root)
  Dir.glob(File.join(plugins_root, '*')).sort.each do |plugin_dir|
    resources = File.join(plugin_dir, 'utssdk', 'app-ios', 'Resources')
    next unless File.directory?(resources)

    existing = project.files.find { |f| f.path.to_s == resources }
    next if existing

    ref = project.main_group.new_file(resources)
    target.resources_build_phase.add_file_reference(ref)
    puts "added plugin resources: #{File.basename(plugin_dir)}"

    plugin_info = File.join(plugin_dir, 'utssdk', 'app-ios', 'Info.plist')
    puts "WARN plugin Info.plist merge required: #{plugin_info}" if File.exist?(plugin_info)
  end
end

abort 'DCloudDebugServe missing from target' unless target.frameworks_build_phase.files.any? { |bf| File.basename(bf.file_ref&.path.to_s) == 'DCloudDebugServe.xcframework' }
project.save
puts 'debug host project saved'
