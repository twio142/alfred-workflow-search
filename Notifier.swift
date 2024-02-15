import Foundation
import AppKit

let fileManager = FileManager.default

extension Collection {
  subscript(safe i: Index) -> Element? {
    return indices.contains(i) ? self[i] : nil
  }
}

func parseArguments() -> (String?, String, String?) {
  var image: String?, appName: String?, targetDir: String?
  let arguments = CommandLine.arguments
  var i = 1
  while i < arguments.count {
    let argument = arguments[i]

    switch argument {
    case "-i":
      i += 1
      if let path = arguments[safe: i], fileManager.fileExists(atPath: path) {
        image = path
      } else {
        print("Image path is invalid.")
      }
    case "-n":
      i += 1
      appName = arguments[safe: i]
    case "-t":
      i += 1
      if let path = arguments[safe: i], fileManager.fileExists(atPath: path) {
        targetDir = path
      } else {
        print("Target directory is invalid.")
      }
    default:
      print("Invalid option: \(argument)")
    }
    i += 1
  }
  return (image, appName ?? "Notifier", targetDir)
}

func randomString(length: Int) -> String {
  var data = Data(count: length)
  let result = data.withUnsafeMutableBytes { bytes -> Int32 in
    SecRandomCopyBytes(kSecRandomDefault, length, bytes.baseAddress!)
  }
  if result == errSecSuccess {
    return data.base64EncodedString()
  } else {
    return String(Int.random(in: 1000000..<9999999))
  }
}

func setBundleID(_ appPath: String) {
  let infoPlistPath = URL(fileURLWithPath: appPath).appendingPathComponent("Contents/Info.plist")
  let bundleId = "com.nyako520.notify." + randomString(length: 9)
  do {
    let data = try Data(contentsOf: infoPlistPath)
    if var plist = try PropertyListSerialization.propertyList(from: data, options: .mutableContainersAndLeaves, format: nil) as? [String: Any] {
      plist["CFBundleIdentifier"] = bundleId
      let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
      try plistData.write(to: infoPlistPath)
    }
  } catch {
    print("Error: \(error.localizedDescription)")
  }
}

func setIcon(_ image: String, _ appPath: String) {
  let tempDir = FileManager.default.temporaryDirectory
  let icnsPath = URL(fileURLWithPath: appPath).appendingPathComponent("Contents/Resources/Applet.icns").path
  let iconSetURL = tempDir.appendingPathComponent("Icon.iconset")
  let sizes = [16, 32, 128, 256, 512]

  do {
    try FileManager.default.createDirectory(at: iconSetURL, withIntermediateDirectories: true, attributes: nil)

    for size in sizes {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
      process.arguments = [
        "-z", "\(size)", "\(size)", image,
        "--out", iconSetURL.appendingPathComponent("icon_\(size)x\(size).png").path
      ]
      process.standardOutput = Pipe()
      try process.run()
      process.waitUntilExit()

      let process2x = Process()
      process2x.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
      process2x.arguments = [
        "-z", "\(size*2)", "\(size*2)", image,
        "--out", iconSetURL.appendingPathComponent("icon_\(size)x\(size)@2x.png").path
      ]
      process2x.standardOutput = Pipe()
      try process2x.run()
      process2x.waitUntilExit()
    }

    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["-c", "icns", "-o", icnsPath, iconSetURL.path]
    iconutil.standardOutput = Pipe()
    try iconutil.run()
    iconutil.waitUntilExit()

    let icon = NSImage.init(contentsOfFile: icnsPath)
    NSWorkspace.shared.setIcon(icon, forFile: appPath)
    try FileManager.default.removeItem(at: iconSetURL)
  } catch {
    print("Error: \(error.localizedDescription)")
    exit(1)
  }
}

func main() {
  var (image, appName, targetDir) = parseArguments()
  guard let image = image else {
    print("Usage: notify -i <image> [-n <app name>] [-t <target dir>]")
    exit(1)
  }
  targetDir = targetDir ?? URL(fileURLWithPath: image).deletingLastPathComponent().path
  let appPath = URL(fileURLWithPath: targetDir!).appendingPathComponent("\(appName).app").path
  if fileManager.fileExists(atPath: appPath) {
    print("App already exists at \(appPath).")
    exit(1)
  }

  do {
    try fileManager.copyItem(at: URL(fileURLWithPath: "./Applet.app"), to: URL(fileURLWithPath: appPath))
  } catch {
    print("Error: \(error.localizedDescription)")
    exit(1)
  }

  setBundleID(appPath)
  setIcon(image, appPath)

  print("App created at \(appPath).")
}

main()