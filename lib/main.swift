import Foundation

func log(_ message: String) {
	if let data = "\(message)\n".data(using: .utf8) {
		FileHandle.standardError.write(data)
	}
}

func matchString(_ query: String, _ string: String) -> Bool {
	let query = query.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).lowercased()
	let matches = string.lowercased().split(whereSeparator: { "_ ".contains($0) })
		.filter { !$0.isEmpty && $0.hasPrefix(query) }
	return matches.count > 0
}

class MyOperation: Operation {
	var result: Workflow?
	var wfId: String
	init(_ wfId: String) {
		self.wfId = wfId
	}
	override func main() {
		result = Workflow(wfId)
	}
}

let env = ProcessInfo().environment
let fileManager = FileManager.default

guard let cacheDir = env["alfred_workflow_cache"], let dataDir = env["alfred_workflow_data"], let alfredPreferences = env["alfred_preferences"], !cacheDir.isEmpty, !dataDir.isEmpty, !alfredPreferences.isEmpty else {
	log("Error: env variables not available")
	exit(1)
}

let cacheBase = URL(fileURLWithPath: cacheDir).deletingLastPathComponent().path
let dataBase = URL(fileURLWithPath: dataDir).deletingLastPathComponent().path
let wfBase = URL(fileURLWithPath: alfredPreferences).appendingPathComponent("workflows").path

if CommandLine.arguments.count > 1 {
	let query = CommandLine.arguments[1].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
	let operationQueue = OperationQueue()
	var items = [] as [Item]
	do {
		let files = try fileManager.contentsOfDirectory(atPath: wfBase)
		for file in files {
			if !file.hasSuffix(".") {
				let operation = MyOperation(file)
				operationQueue.addOperation(operation)
			}
		}
		operationQueue.operations.forEach {
			$0.waitUntilFinished()
			if let workflow = ($0 as? MyOperation)?.result as? Workflow, !workflow.disabled {
        if query.hasPrefix("\(workflow.name)::") {
          let subQuery = query.replacingOccurrences(of: "\(workflow.name)::", with: "")
          items += workflow.matchForKeywords(subQuery)
        } else {
          items += workflow.matchForWorkflow(query)
          if !query.isEmpty {
            items += workflow.matchForKeywords(query)
          }
        }
			}
		}
		if items.count == 0 {
			items.append(warnEmpty("No Workflow Found :{"))
		} else {
			items.sort(by: { (a, b) -> Bool in
				return (a.uid != nil ? 0 : 1) < (b.uid != nil ? 0 : 1)
			})
		}
	} catch {
		log("Error: \(error.localizedDescription)")
		items.insert(warnEmpty("Error: \(error.localizedDescription)"), at: 0)
	}
	let json = try! JSONEncoder().encode(["items": items])
	print(String(data: json, encoding: .utf8)!)
}