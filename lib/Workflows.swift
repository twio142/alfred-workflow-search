import Foundation
let SHIFT = "\u{21E7}"
let CONTROL = "\u{2303}"
let COMMAND = "\u{2318}"
let OPTION = "\u{2325}"
let FN = "fn"

let MODIFIERS = [
	131072   : SHIFT,
	262144   : CONTROL,
	262401   : CONTROL,
	393216   : SHIFT+CONTROL,
	524288   : OPTION,
	655360   : SHIFT+OPTION,
	786432   : CONTROL+OPTION,
	917504   : SHIFT+CONTROL+OPTION,
	1048576  : COMMAND,
	1179648  : SHIFT+COMMAND,
	1310720  : CONTROL+COMMAND,
	1310985  : CONTROL+COMMAND,
	1441792  : SHIFT+CONTROL+COMMAND,
	1572864  : OPTION+COMMAND,
	1703936  : SHIFT+OPTION+COMMAND,
	1835008  : CONTROL+OPTION+COMMAND,
	1966080  : SHIFT+CONTROL+OPTION+COMMAND,
	8388608  : FN,
	8519680  : SHIFT,
	11272192 : CONTROL+OPTION
]

enum KeywordType: String, CaseIterable {
	case Keyword = "Keyword"
	case Snippet = "Snippet"
	case Action = "Action"
	case External = "External"
	case Hotkey = "Hotkey"
}

struct Keyword {
	var title: String = ""
	var keyword: String = ""
	var type: KeywordType
	var script: String = ""
	let id: String
}

class Workflow {
	var wfId: String
	var disabled: Bool = true
	var name: String = ""
	var bundleId: String = ""
	var version: String = ""
	var description: String = ""
	var website: String = ""
	var keywords: [Keyword] = []
	var wfDir: String {
		return URL(fileURLWithPath: wfBase).appendingPathComponent(wfId).path
	}
	var cacheDir: String? = nil
	var dataDir: String? = nil

	init(_ wfId: String) {
		self.wfId = wfId
		readObjects()
	}

	func readPlist() -> [String: Any]? {
    let infoFile = URL(fileURLWithPath: self.wfDir).appendingPathComponent("info.plist")
    guard let data = try? Data(contentsOf: infoFile),
			let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
			return nil
    }
		self.disabled = plist["disabled"] as? Bool ?? true
		self.name = plist["name"] as? String ?? ""
		if self.disabled { return nil }
		self.bundleId = plist["bundleid"] as? String ?? ""
		if !self.bundleId.isEmpty {
			self.cacheDir = URL(fileURLWithPath: cacheBase).appendingPathComponent(self.bundleId).path
			if !fileManager.fileExists(atPath: self.cacheDir!) {
				self.cacheDir = nil
			}
			self.dataDir = URL(fileURLWithPath: dataBase).appendingPathComponent(self.bundleId).path
			if !fileManager.fileExists(atPath: self.dataDir!) {
				self.dataDir = nil
			}
		}
		self.description = plist["description"] as? String ?? ""
		self.version = plist["version"] as? String ?? ""
		self.website = plist["webaddress"] as? String ?? ""
    return plist
	}

	func readObjects() {
		guard let plist = readPlist(), let objects = plist["objects"] as? [[String: Any]] else {
			return
		}
		for object in objects {
			let type = object["type"] as? String ?? ""
			let uid = object["uid"] as? String ?? ""
			guard let config = object["config"] as? [String: Any] else {
				continue
			}
			let inboundConfig = object["inboundconfig"] as? [String:Any]
			if type.hasPrefix("alfred.workflow.input") {
				if (config["keyword"] == nil && inboundConfig == nil) {
					continue
				}
				var k = Keyword(type: .Keyword, id: uid)
				if let title = config["title"] as? String {
					k.title = title
				} else if let title = config["text"] as? String {
					k.title = title
				}
				k.title = k.title.replacingOccurrences(of: "{query}", with: "{\u{0019}query}")
				if let scriptFile = config["scriptfile"] as? String, !scriptFile.isEmpty {
					k.script = URL(fileURLWithPath: self.wfDir).appendingPathComponent(scriptFile).path
				}
				if let inboundConfig = inboundConfig, let externalId = inboundConfig["externalid"] as? String, !externalId.isEmpty {
					k.keyword = externalId
					k.type = .External
					self.keywords.append(k)
				}
				guard var keyword = config["keyword"] as? String, !keyword.isEmpty else {
					continue
				}
				if keyword.range(of: "\\{var:.+\\}", options: .regularExpression) != nil {
					keyword = getVariablesInKeyword(keyword, plist)
				}
				self.keywords.append(Keyword(title: k.title, keyword: keyword, type: .Keyword, script: k.script, id: uid))
			} else if type == "alfred.workflow.trigger.snippet" {
				self.keywords.append(Keyword(keyword: config["keyword"] as? String ?? "", type: .Snippet, id: uid))
			} else if type == "alfred.workflow.trigger.action" || type == "alfred.workflow.trigger.universalaction", let action = config["name"] as? String, !action.isEmpty {
				self.keywords.append(Keyword(keyword: action, type: .Action, id: uid))
			} else if let inboundConfig = inboundConfig, let externalId = inboundConfig["externalid"] as? String, !externalId.isEmpty {
				var k = Keyword(keyword: externalId, type: .External, id: uid)
				if let scriptFile = config["scriptfile"] as? String, !scriptFile.isEmpty {
					k.script = URL(fileURLWithPath: self.wfDir).appendingPathComponent(scriptFile).path
				}
				self.keywords.append(k)
			} else if type == "alfred.workflow.trigger.external", let triggerId = config["triggerid"] as? String, !triggerId.isEmpty {
				self.keywords.append(Keyword(keyword: triggerId, type: .External, id: uid))
			} else if type == "alfred.workflow.trigger.hotkey", let key = config["hotstring"] as? String, !key.isEmpty {
				var k = Keyword(keyword: key, type: .Hotkey, id: uid)
				if let mod = config["hotmod"] as? Int, let modifier = MODIFIERS[mod] {
					k.keyword = modifier + " " + k.keyword
				}
				if let uiData = plist["uidata"] as? [String: Any], let element = uiData[uid] as? [String: Any], let note = element["note"] as? String, !note.isEmpty {
					k.title = note
				}
				self.keywords.append(k)
			}
		}
	}

	func matchForWorkflow(_ query: String) -> [Item] {
		if query.split(separator: " ").allSatisfy( { matchString(String($0), name) } ) {
			return [outputWorkflow()]
		}
		return []
	}

	func matchForKeywords(_ query: String) -> [Item] {
		var query = query
		var specifiedTypes = [KeywordType]()
		query.split(separator: " ").forEach { q in
			KeywordType.allCases.forEach { type in
				if "[\(type.rawValue.lowercased())]".hasPrefix(q.lowercased()) && !specifiedTypes.contains(type) {
					specifiedTypes.append(type)
					query = query.replacingOccurrences(of: q, with: "")
				}
			}
		}
		if specifiedTypes.count == 0 {
			specifiedTypes = KeywordType.allCases
		}
		query = String(query.split(separator: " ").first ?? "")
		return self.keywords.filter {
			specifiedTypes.contains($0.type) && matchString(query, $0.keyword)
		} .map {
			outputKeyword($0)
		}
	}

	func getVariablesInKeyword(_ keyword: String, _ plist: [String: Any]) -> String {
		var keyword = keyword
		let regex = try! NSRegularExpression(pattern: "\\{var:([^\\}]+)\\}", options: [])
		let ranges = regex.matches(in: keyword, options: [], range: NSRange(keyword.startIndex..., in: keyword))
		let keys = ranges.map { keyword[Range($0.range(at: 1), in: keyword)!] }
		let variables = plist["variables"] as? [String:String]
		var prefs: NSDictionary?
		let path = URL(fileURLWithPath: self.wfDir).appendingPathComponent("prefs.plist").path
		if fileManager.fileExists(atPath: path) {
			prefs = NSDictionary(contentsOfFile: path)
		}
		let userConfig = plist["userconfigurationconfig"] as? [[String: Any]]
		for key in keys {
			var value: String?
			if let variables = variables, let variable = variables[String(key)] {
				value = variable
			} else if let prefs = prefs, let variable = prefs[String(key)] as? String {
				value = variable
			} else if let userConfig = userConfig, let config = userConfig.first(where: { $0["variable"] as? String == String(key) }), let defaultValue = config["config"] as? [String: Any] {
				value = defaultValue["default"] as? String
			}
			keyword = keyword.replacingOccurrences(of: "{var:\(key)}", with: value ?? "{\u{0019}var:\(key)}")
		}
		return keyword
	}

	func outputKeyword(_ k: Keyword) -> Item {
		var icon = URL(fileURLWithPath: self.wfDir).appendingPathComponent("\(k.id).png").path
		if !fileManager.fileExists(atPath: icon) {
			icon = URL(fileURLWithPath: self.wfDir).appendingPathComponent("icon.png").path
		}
		var item = Item(
			title: "[\(k.type)] \(k.keyword)",
			subtitle: self.name + " - " + (k.title.isEmpty ? "[no title]" : k.title) + (k.script.isEmpty ? "" : " 📄"),
			arg: "alfredpreferences:workflows>workflow>\(self.wfId)>\(k.id)",
			quicklookurl: k.script,
			icon: Item.Icon(path: icon)
		)
		item.setMod(.shift, Item.Mod(
			arg: self.wfDir,
			subtitle: "Open folder in Alfred",
			variables: [ "mod": "browse" ]
		))
		if k.type == KeywordType.External {
			item.text = Item.Text(copy: "altr -w \(self.bundleId) -t \(k.keyword) -a ")
		}
		if !k.script.isEmpty {
			item.setAction(.file, .string(k.script))
		}
		if let dir = self.cacheDir {
			item.setMod(.ctrl, Item.Mod(
				arg: dir,
				subtitle: "Open cache folder in Alfred",
				variables: [ "mod": "browse" ]
			))
		}
		if let dir = self.dataDir {
			item.setMod(.fn, Item.Mod(
				arg: dir,
				subtitle: "Open data folder in Alfred",
				variables: [ "mod": "browse" ]
			))
		}
		return item
	}

	func outputWorkflow() -> Item {
		var item = Item(
			title: self.name,
			subtitle: self.keywords.map( { $0.keyword } ).joined(separator: " · "),
			arg: "alfredpreferences:workflows>workflow>\(self.wfId)",
			uid: self.wfId,
			autocomplete: self.name + "::",
			quicklookurl: self.website,
			icon: Item.Icon(path: "\(self.wfDir)/icon.png" )
		)
		if !self.version.isEmpty || !self.description.isEmpty {
			let subtitle = [self.version, self.description].filter( { !$0.isEmpty } ).joined(separator: "  |  ")
			item.setMod(.cmd, Item.Mod(
				valid: false,
				subtitle: subtitle
			))
		}
		item.setMod(.shift, Item.Mod(
			arg: self.wfDir,
			subtitle: "Open folder in Alfred",
			variables: [ "mod": "browse" ]
		))
		item.setAction(.file, .string(self.wfDir))
		if let dir = self.cacheDir {
			item.setMod(.ctrl, Item.Mod(
				arg: dir,
				subtitle: "Open cache folder in Alfred",
				variables: [ "mod": "browse" ]
			))
		}
		if let dir = self.dataDir {
			item.setMod(.fn, Item.Mod(
				arg: dir,
				subtitle: "Open data folder in Alfred",
				variables: [ "mod": "browse" ]
			))
		}
		return item
	}
}
