import Foundation

struct Item: Codable {
  struct Icon: Codable {
    let path: String
  }
  struct Text: Codable {
    var copy: String?
    var largetype: String?
  }
  enum ModKey: String, Codable {
    case cmd = "cmd"
    case alt = "alt"
    case ctrl = "ctrl"
    case shift = "shift"
    case fn = "fn"
  }
  struct Mod: Codable {
    var valid: Bool = true
    var arg: String = ""
    var subtitle: String?
    var icon: Icon?
    var variables: [String: String] = [:]
  }
  enum ActionType: String, Codable {
    case auto = "auto"
    case file = "file"
    case text = "text"
    case url = "url"
  }
	enum Action: Codable {
    case string(String)
    case array([String])
		func encode(to encoder: Encoder) throws {
			var container = encoder.singleValueContainer()
			switch self {
			case .string(let value):
				try container.encode(value)
			case .array(let value):
				try container.encode(value)
			}
		}
  }
  var title: String
  var subtitle: String = ""
  var arg: String = ""
	var uid: String? = nil
  var valid: Bool = true
	var autocomplete: String? = nil
	var quicklookurl: String? = nil
  var icon: Icon?
  var text: Text?
  var variables: [String: String] = [:]
  var mods: [String: Mod] = [:]
  var action: [String: Action] = [:]

  mutating func setMod(_ key: ModKey, _ mod: Mod) {
    mods[key.rawValue] = mod
  }
  mutating func setAction(_ key: ActionType, _ value: Action) {
    action[key.rawValue] = value
  }
}

func warnEmpty(_ title: String) -> Item {
	return Item(
		title: title,
		valid: false,
		icon: Item.Icon(path: "../../resources/AlertCautionIcon.icns")
	)
}