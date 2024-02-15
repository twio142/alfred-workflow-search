import Foundation

enum KeywordType: String, CaseIterable {
	case Keyword = "Keyword"
	case Snippet = "Snippet"
	case Action = "Action"
	case External = "External"
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
	var website: String = ""
	var keywords: [Keyword] = []
	var wfDir: String {
		return URL(fileURLWithPath: wfBase).appendingPathComponent(wfId).path
	}
	var cacheDir: String = ""
	var dataDir: String = ""

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
			if !fileManager.fileExists(atPath: self.cacheDir) {
				self.cacheDir = ""
			}
			self.dataDir = URL(fileURLWithPath: dataBase).appendingPathComponent(self.bundleId).path
			if !fileManager.fileExists(atPath: self.dataDir) {
				self.dataDir = ""
			}
		}
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
			}
		}
	}

	func matchForWorkflow(_ query: String) -> [Item] {
		if query.split(separator: " ").allSatisfy( { matchString(String($0), name) } ) {
			var item = Item(
				title: name,
				subtitle: self.keywords.map( { $0.keyword } ).joined(separator: " · "),
				arg: "alfredpreferences:workflows>workflow>\(self.wfId)",
				uid: self.wfId,
				autocomplete: self.name + "::",
				quicklookurl: self.website,
				icon: Item.Icon(path: "\(self.wfDir)/icon.png" )
			)
			item.setMod(.shift, Item.Mod(
				arg: self.wfDir,
				subtitle: "Open folder in Alfred",
				variables: [ "mod": "browse" ]
			))
			item.setAction(.file, .string(self.wfDir))
			if !self.cacheDir.isEmpty {
				item.setMod(.ctrl, Item.Mod(
					arg: self.cacheDir,
					subtitle: "Open cache folder in Alfred",
					variables: [ "mod": "browse" ]
				))
			}
			if !self.dataDir.isEmpty {
				item.setMod(.fn, Item.Mod(
					arg: self.dataDir,
					subtitle: "Open data folder in Alfred",
					variables: [ "mod": "browse" ]
				))
			}
			return [item]
		}
		return []
	}

	func matchForKeywords(_ query: String) -> [Item] {
		var specifiedTypes = [KeywordType]()
		var query_ = query
		query.split(separator: " ").forEach { q in
			KeywordType.allCases.forEach { type in
				if "[\(type.rawValue.lowercased())]".hasPrefix(q.lowercased()) && !specifiedTypes.contains(type) {
					specifiedTypes.append(type)
					query_ = query_.replacingOccurrences(of: q, with: "")
				}
			}
		}
		if specifiedTypes.count == 0 {
			specifiedTypes = KeywordType.allCases
		}
		query_ = String(query_.split(separator: " ").first ?? "")
		return self.keywords.filter {
			specifiedTypes.contains($0.type) && matchString(query_, $0.keyword)
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
		let wfDir = URL(fileURLWithPath: wfBase).appendingPathComponent(self.wfId).path
		var icon = URL(fileURLWithPath: wfDir).appendingPathComponent("\(k.id).png").path
		if !fileManager.fileExists(atPath: icon) {
			icon = URL(fileURLWithPath: wfDir).appendingPathComponent("icon.png").path
		}
		var item = Item(
			title: "[\(k.type)] \(k.keyword)",
			subtitle: self.name + " - " + (k.title.isEmpty ? "[no title]" : k.title) + (k.script.isEmpty ? "" : " 📄"),
			arg: "alfredpreferences:workflows>workflow>\(self.wfId)>\(k.id)",
			quicklookurl: k.script,
			icon: Item.Icon(path: icon)
		)
		item.setMod(.shift, Item.Mod(
			arg: wfDir,
			subtitle: "Open folder in Alfred",
			variables: [ "mod": "browse" ]
		))
		if k.type == KeywordType.Keyword {
			item.text = Item.Text(copy: "~/bin/altr -w \(self.bundleId) -t \(k.keyword) -a ")
		}
		if !k.script.isEmpty {
			item.setAction(.file, .string(k.script))
		}
		if !self.cacheDir.isEmpty {
			item.setMod(.ctrl, Item.Mod(
				arg: self.cacheDir,
				subtitle: "Open cache folder in Alfred",
				variables: [ "mod": "browse" ]
			))
		}
		if !self.dataDir.isEmpty {
			item.setMod(.fn, Item.Mod(
				arg: self.dataDir,
				subtitle: "Open data folder in Alfred",
				variables: [ "mod": "browse" ]
			))
		}
		return item
	}
}