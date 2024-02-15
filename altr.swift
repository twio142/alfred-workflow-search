import Foundation

extension Collection {
    subscript(safe i: Index) -> Element? {
        return indices.contains(i) ? self[i] : nil
    }
}

struct AlfredWorkflow: Encodable {
    struct Config: Encodable {
        let workflowbundleid: String
        let externaltriggerid: String
    }
    let config: Config
    let arg: String
    let variables: [String: String]
}

func parseArguments() -> AlfredWorkflow? {
    var workflow: String?
    var trigger: String?
    var arg: String?
    var variables: [String: String] = [:]

    var index = 1
    while index < CommandLine.arguments.count {
        let argument = CommandLine.arguments[index]

        switch argument {
        case "-w", "--workflow":
            workflow = CommandLine.arguments[safe: index + 1]
            index += 2
        case "-t", "--trigger":
            trigger = CommandLine.arguments[safe: index + 1]
            index += 2
        case "-a", "--arg":
            arg = CommandLine.arguments[safe: index + 1]
            index += 2
        case "-v", "--var":
            if let range = CommandLine.arguments[safe: index + 1]?.range(of: "="), range.lowerBound > CommandLine.arguments[index + 1].startIndex {
                let key = CommandLine.arguments[index + 1][..<range.lowerBound]
                let value = CommandLine.arguments[index + 1][range.upperBound...]
                variables[String(key)] = String(value)
            }
            index += 2
        default:
            index += 1
        }
    }

    workflow = workflow ?? ProcessInfo.processInfo.environment["alfred_workflow_bundleid"]

    if let workflow = workflow, let trigger = trigger {
        return AlfredWorkflow(
            config: AlfredWorkflow.Config(workflowbundleid: workflow, externaltriggerid: trigger),
            arg: arg ?? "",
            variables: variables
        )
    }
    return nil
}

func formatJSONString(_ config: AlfredWorkflow) -> String {
    do {
        let json = try JSONEncoder().encode(["alfredworkflow": config])
        return String(data: json, encoding: .utf8) ?? ""
    } catch {
        print("Error serializing JSON: \(error.localizedDescription)")
        return ""
    }
}

func openAlfredURL(_ jsonString: String) {
    var allowedCharacters = CharacterSet.urlQueryAllowed
    allowedCharacters.remove(charactersIn: "&")
    let encodedJsonString = jsonString.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? ""
    let url = "alfred://runtrigger/com.nyako520.alfred/trigger/?argument=\(encodedJsonString)"
    let process = Process()
    process.launchPath = "/usr/bin/open"
    process.arguments = ["-g", url]
    process.launch()
}

if let config = parseArguments() {
    let json = formatJSONString(config)
    openAlfredURL(json)
} else {
    print("Run Alfred trigger with argument and variables.")
    print("Usage: altr -w WORKFLOW -t TRIGGER [-a ARGUMENT] [-v KEY1=VALUE1] [-v KEY2=VALUE2] ...")
}
