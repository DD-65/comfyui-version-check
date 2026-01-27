#!/usr/bin/env swift
import Foundation

enum CheckError: Error, CustomStringConvertible {
    case plistReadFailed(String)
    case versionMissing(String)
    case urlInvalid(String)
    case networkFailed(String)
    case badHTTP(Int)
    case jsonParseFailed(String)

    var description: String {
        switch self {
        case .plistReadFailed(let s): return "plist read failed: \(s)"
        case .versionMissing(let s): return "version missing: \(s)"
        case .urlInvalid(let s): return "url invalid: \(s)"
        case .networkFailed(let s): return "network failed: \(s)"
        case .badHTTP(let code): return "bad HTTP status: \(code)"
        case .jsonParseFailed(let s): return "json parse failed: \(s)"
        }
    }
}

func normalize(_ s: String) -> String {
    // Trim + drop a single leading "v" or "V"
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.count >= 2, (t.first == "v" || t.first == "V") {
        return String(t.dropFirst())
    }
    return t
}

func parseVersion(_ s: String) -> [Int] {
    // Keep only numeric-dot parts; map empty/invalid segments to 0
    let cleaned = s.trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned
        .split(separator: ".")
        .map { Int($0) ?? 0 }
}

func compareSemver(_ a: String, _ b: String) -> ComparisonResult {
    let va = parseVersion(a)
    let vb = parseVersion(b)
    let n = max(va.count, vb.count)
    for i in 0..<n {
        let ai = i < va.count ? va[i] : 0
        let bi = i < vb.count ? vb[i] : 0
        if ai < bi { return .orderedAscending }
        if ai > bi { return .orderedDescending }
    }
    return .orderedSame
}

func readPlistVersion(plistPath: String) throws -> String {
    let url = URL(fileURLWithPath: plistPath)
    let data: Data
    do {
        data = try Data(contentsOf: url)
    } catch {
        throw CheckError.plistReadFailed(error.localizedDescription)
    }

    let obj: Any
    do {
        obj = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    } catch {
        throw CheckError.plistReadFailed(error.localizedDescription)
    }

    guard
        let dict = obj as? [String: Any],
        let v = dict["CFBundleShortVersionString"] as? String,
        !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
        throw CheckError.versionMissing("CFBundleShortVersionString not found in \(plistPath)")
    }

    return normalize(v)
}

func fetchLatestTag() throws -> String {
    let s = "https://api.github.com/repos/Comfy-Org/desktop/releases/latest"
    guard let url = URL(string: s) else { throw CheckError.urlInvalid(s) }

    var req = URLRequest(url: url)
    req.httpMethod = "GET"
    // GitHub API best-practice headers
    req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    req.setValue("comfyui-version-check", forHTTPHeaderField: "User-Agent")

    let sem = DispatchSemaphore(value: 0)
    var result: Result<String, Error> = .failure(CheckError.networkFailed("unknown"))

    URLSession.shared.dataTask(with: req) { data, resp, err in
        defer { sem.signal() }

        if let err = err {
            result = .failure(CheckError.networkFailed(err.localizedDescription))
            return
        }

        guard let http = resp as? HTTPURLResponse else {
            result = .failure(CheckError.networkFailed("no HTTP response"))
            return
        }

        guard (200...299).contains(http.statusCode) else {
            result = .failure(CheckError.badHTTP(http.statusCode))
            return
        }

        guard let data = data else {
            result = .failure(CheckError.networkFailed("empty body"))
            return
        }

        do {
            let obj = try JSONSerialization.jsonObject(with: data, options: [])
            guard
                let dict = obj as? [String: Any],
                let tag = dict["tag_name"] as? String,
                !tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                result = .failure(CheckError.jsonParseFailed("missing tag_name"))
                return
            }
            result = .success(normalize(tag))
        } catch {
            result = .failure(CheckError.jsonParseFailed(error.localizedDescription))
        }
    }.resume()

    _ = sem.wait(timeout: .now() + 20) // 20s timeout
    switch result {
    case .success(let tag): return tag
    case .failure(let e): throw e
    }
}

func main() -> Int32 {
    let plistPath = CommandLine.arguments.dropFirst().first
        ?? "/Applications/ComfyUI.app/Contents/Info.plist"

    do {
        let local = try readPlistVersion(plistPath: plistPath)
        let remote = try fetchLatestTag()

        let cmp = compareSemver(local, remote)
        if cmp == .orderedSame {
            print("NO: local \(local) == remote \(remote)")
            return 0
        } else if cmp == .orderedAscending {
            print("UPDATE!!: local \(local) < remote \(remote)")
            return 1
        } else {
            print("AHEAD: local \(local) > remote \(remote)")
            return 0
        }
    } catch {
        fputs("ERROR: \(error)\n", stderr)
        return 2
    }
}

exit(main())
