#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

ruby <<'RUBY'
require "json"
require "open3"
require "rexml/document"

errors = []
strings_files = Dir["iina/*.lproj/*.strings"].sort
locale_dirs = Dir["iina/*.lproj"].select { |path| File.directory?(path) }.sort
user_locales = locale_dirs.reject { |path| File.basename(path) == "Base.lproj" }
required_about_keys = %w[
  about.overview.tagline
  about.overview.website
  about.overview.source_code
  about.overview.license
]
required_common_keys = %w[brand.localized_name]

project_json, project_stderr, project_status = Open3.capture3(
  "plutil", "-convert", "json", "-o", "-", "iina.xcodeproj/project.pbxproj"
)
unless project_status.success?
  errors << "Invalid Xcode project: #{project_stderr.strip}"
  active_locales = []
else
  project = JSON.parse(project_json).fetch("objects").values.find { |object| object["isa"] == "PBXProject" }
  active_locales = project.fetch("knownRegions").reject { |locale| locale == "Base" }.sort
end

strings_files.each do |path|
  json, stderr, status = Open3.capture3("plutil", "-convert", "json", "-o", "-", path)
  unless status.success?
    errors << "Invalid strings file #{path}: #{stderr.strip}"
    next
  end

  JSON.parse(json).each do |key, value|
    next unless value.is_a?(String)
    if value.match?(%r{github\.com/iina/iina|developers@iina\.io|https?://iina\.io}i)
      errors << "Upstream support URL in #{path} key #{key}"
    end

    compatibility_stripped = value.gsub(/\.iinaplgz|\.iinaplugin|iina:\/\//i, "")
    if compatibility_stripped.match?(/\bIINA\b/i)
      errors << "Old product name in #{path} key #{key}"
    end
  end
end

user_locales.each do |locale_dir|
  path = File.join(locale_dir, "Localizable.strings")
  json, stderr, status = Open3.capture3("plutil", "-convert", "json", "-o", "-", path)
  unless status.success?
    errors << "Invalid strings file #{path}: #{stderr.strip}"
    next
  end

  values = JSON.parse(json)
  required_common_keys.each do |key|
    errors << "Missing #{key} in #{path}" unless values.key?(key)
  end
  required_about_keys.each do |key|
    errors << "Missing #{key} in #{path}" unless values[key].is_a?(String) && !values[key].empty?
  end
end

visible_attributes = %w[title toolTip label placeholderString messageText informativeText]
Dir["iina/Base.lproj/*.{xib,storyboard}", "OpenInIINA/**/*.{xib,storyboard}"].sort.each do |path|
  document = REXML::Document.new(File.read(path))
  REXML::XPath.each(document, "//*") do |element|
    visible_attributes.each do |attribute|
      value = element.attributes[attribute]
      next unless value
      if value.match?(/\bIINA\b|github\.com\/iina\/iina|developers@iina\.io|https?:\/\/iina\.io/i)
        errors << "Old visible branding in #{path} #{attribute}=#{value.inspect}"
      end
    end
  end
end

{
  "iina/Info.plist" => %w[CFBundleDisplayName CFBundleName],
  "OpenInIINA/Info.plist" => %w[CFBundleDisplayName CFBundleName SFSafariToolbarItemDescription]
}.each do |path, keys|
  json, stderr, status = Open3.capture3("plutil", "-convert", "json", "-o", "-", path)
  unless status.success?
    errors << "Invalid plist #{path}: #{stderr.strip}"
    next
  end
  values = JSON.parse(json)
  keys.each do |key|
    value = values[key]
    next unless value.is_a?(String)
    errors << "Old product name in #{path} key #{key}" if value.match?(/\bIINA\b/i)
  end
end

unless user_locales.length == 54
  errors << "Expected 54 user locales, found #{user_locales.length}"
end

source_locale_names = user_locales.map { |path| File.basename(path, ".lproj") }
missing_active_locales = active_locales - source_locale_names
unless missing_active_locales.empty?
  errors << "Active Xcode locales without source directories: #{missing_active_locales.join(', ')}"
end

if errors.any?
  warn errors.join("\n")
  exit 1
end

puts "Branding check passed for #{user_locales.length} locale source trees " \
     "(#{active_locales.length} active build locales), Base resources, and app metadata."
RUBY

for forbidden in \
  'reason: "IINA' \
  'Logger.log("IINA ' \
  'print("IINA ' \
  'filename: "iina.log"' \
  'iina-debug-dump-' \
  'return "IINA v' \
  'highlightsLink = "https://iina.io' \
  'sectionBrowserExtView' \
  'extChromeBtnAction' \
  'extFirefoxBtnAction' \
  'chromeExtensionLink' \
  'firefoxExtensionLink'; do
  if rg -n -F "$forbidden" iina OpenInIINA >/dev/null; then
    echo "User-visible source branding remains: ${forbidden}" >&2
    rg -n -F "$forbidden" iina OpenInIINA >&2
    exit 1
  fi
done
