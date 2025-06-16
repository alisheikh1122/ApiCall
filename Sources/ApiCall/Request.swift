import Foundation
@available(macOS 10.15.0, *)
@available(iOS 13.0.0, *)
public class Request : @unchecked Sendable {
    public static let shared = Request()
    var BASE_URL = String()
    var header = [String: String]()
    var errorModel: Codable?
    var isFormUrlEncoded: Bool?
    var isMultipartFormData: Bool?
    var isDebuggingEnabled = false

    public func setupVariables(baseUrl: String, header: [String: String], errorModel: Codable? = nil, isFormUrlEncoded: Bool? = false,isMultipartFormData: Bool? = false, isDebuggingEnabled: Bool = false) {
        Request.shared.BASE_URL = baseUrl
        Request.shared.header = header
        Request.shared.errorModel = errorModel
        Request.shared.isFormUrlEncoded = isFormUrlEncoded
        Request.shared.isDebuggingEnabled = isDebuggingEnabled
        Request.shared.isMultipartFormData = isMultipartFormData
    }

    public func requestApi<T: Codable>(_ type: T.Type, baseUrl: String? = nil, method: HTTPMethod, url: String, params: [String: Any]? = nil,paramsArray: [[String: Any]]? = nil, isCamelCase: Bool? = true,isMultipartFormData : Bool = false ) async throws -> T {
        if !NetworkReachability.isConnectedToNetwork() {
            throw ServiceError.noInternetConnection
        }
        
        var request = URLRequest(url: URL(string: ((baseUrl != nil ? baseUrl : BASE_URL) ?? BASE_URL) + url)!)
        if isMultipartFormData {
            let boundary = "Boundary-\(UUID().uuidString)"
            header.updateValue("multipart/form-data; boundary=\(boundary)", forKey: "Content-Type")
            
            if let paramsArray = paramsArray {
                request.httpBody = createMultipartBody(paramsArray: paramsArray, boundary: boundary)
            }
        } else if isFormUrlEncoded == true {
            header.updateValue("application/x-www-form-urlencoded", forKey: "Content-Type")
            if let params {
                let queryString = getqueryString(dict: params)
                request.httpBody = queryString.data(using: .utf8)
            }
        } else {
            header.updateValue("application/json", forKey: "Content-Type")
            if let params = params {
                let postData = try JSONSerialization.data(withJSONObject: params, options: .prettyPrinted)
                request.httpBody = postData
            }
            
        }
        request.allHTTPHeaderFields = header
        request.httpMethod = method.rawValue

        let (data, response) = try await URLSession.shared.data(for: request)
        
        if isDebuggingEnabled {
            print("----------Request----------")
            print(String(describing: ((baseUrl != nil ? baseUrl : BASE_URL) ?? BASE_URL) + url))
            
            if let headersData = try? JSONSerialization.data(withJSONObject: header, options: .prettyPrinted) {
                print("----------Headers----------")
                print(String(decoding: headersData, as: UTF8.self))
            }
            
            if let params, let paramsData = try? JSONSerialization.data(withJSONObject: params, options: .prettyPrinted) {
                print("----------Parameters----------")
                print(String(decoding: paramsData, as: UTF8.self))
            }
            
            print("----------RESPONSE----------")
            if let json = try? JSONSerialization.jsonObject(with: data, options: .mutableContainers),
               let jsonData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted) {
                print(String(decoding: jsonData, as: UTF8.self))
            } else {
                print("json data malformed")
            }
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.custom("Invalid response")
        }

        switch httpResponse.status?.responseType {
        case .success,.redirection,.clientError,.serverError:
            let decoder = JSONDecoder()
            if isCamelCase == true {
                decoder.keyDecodingStrategy = .convertFromSnakeCase
            }
            let JSON = try decoder.decode(type, from: data)
            return JSON
        default:
            print("----------Error----------")
            print("Error code: \(String(describing: httpResponse.status))")
            throw ServiceError.custom("Error code: \(String(describing: httpResponse.status))")
        }
    }

    public func uploadData<T: Codable>(_ type: T.Type, baseUrl: String? = nil, method: HTTPMethod, imageData: Data, url: String, params: [String: String]? = nil, bearerToken : String? = nil, isCamelCase: Bool? = true, imageName: String) async throws -> T {
        if !NetworkReachability.isConnectedToNetwork() {
            throw ServiceError.noInternetConnection
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: ((baseUrl != nil ? baseUrl : BASE_URL) ?? BASE_URL) + url)!)
        request.httpMethod = method.rawValue
        header.updateValue("multipart/form-data; boundary=\(boundary)", forKey: "Content-Type")
        if let bearerToken {
            header.updateValue("Bearer \(bearerToken)", forKey: "Authorization")
            header.updateValue("application/json", forKey: "Accept")
        }
        request.allHTTPHeaderFields = header
        let httpBody = NSMutableData()

        if let params = params {
            for (key, value) in params {
                httpBody.appendString(convertFormField(named: key, value: value, using: boundary))
            }
        }

        httpBody.append(convertFileData(fieldName: imageName,
                                        fileName: "imagename.png",
                                        mimeType: "image/jpe",
                                        fileData: imageData,
                                        using: boundary))
        httpBody.appendString("--\(boundary)--")

        request.httpBody = httpBody as Data
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        
        if isDebuggingEnabled {
            print("----------Request----------")
            print(String(describing: ((baseUrl != nil ? baseUrl : BASE_URL) ?? BASE_URL) + url))
            
            if let headersData = try? JSONSerialization.data(withJSONObject: header, options: .prettyPrinted) {
                print("----------Headers----------")
                print(String(decoding: headersData, as: UTF8.self))
            }
            
            if let params, let paramsData = try? JSONSerialization.data(withJSONObject: params, options: .prettyPrinted) {
                print("----------Parameters----------")
                print(String(decoding: paramsData, as: UTF8.self))
            }
            
            print("----------RESPONSE----------")
            if let json = try? JSONSerialization.jsonObject(with: data, options: .mutableContainers),
               let jsonData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted) {
                print(String(decoding: jsonData, as: UTF8.self))
            } else {
                print("json data malformed")
            }
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.custom("Invalid response")
        }

        switch httpResponse.status?.responseType {
        case .success:
            let JSON = try JSONDecoder().decode(type, from: data)
            return JSON
        default:
            let JSON = try JSONDecoder().decode(ErrorModel.self, from: data)
            throw ServiceError.custom(JSON.errors.first?.message ?? "")
        }
    }
    
    func convertFormField(named name: String, value: String, using boundary: String) -> String {
        var fieldString = "--\(boundary)\r\n"
        fieldString += "Content-Disposition: form-data; name=\"\(name)\"\r\n"
        fieldString += "\r\n"
        fieldString += "\(value)\r\n"

        return fieldString
    }

    func convertFileData(fieldName: String, fileName: String, mimeType: String, fileData: Data, using boundary: String) -> Data {
        let data = NSMutableData()

        data.appendString("--\(boundary)\r\n")
        data.appendString("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n")
        data.appendString("Content-Type: \(mimeType)\r\n\r\n")
        data.append(fileData)
        data.appendString("\r\n")

        return data as Data
    }
    
    func getqueryString(dict: [String: Any]) -> String {
        var output: String = ""
        for (key,value) in dict {
            output +=  "\(key)=\(value)&"
        }
        output = String(output.dropLast())
        return output
    }
    func getQueryString(from array: [[String: Any]]) -> String {
        var components: [String] = []

        for dict in array {
            for (key, value) in dict {
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
                let encodedValue = "\(value)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "\(value)"
                components.append("\(encodedKey)=\(encodedValue)")
            }
        }

        return components.joined(separator: "&")
    }
    private func createMultipartBody(paramsArray: [[String: Any]], boundary: String) -> Data {
        var body = Data()
        
        for param in paramsArray {
            guard
                let key = param["key"] as? String,
                let value = param["value"],
                let type = param["type"] as? String
            else {
                continue
            }
            
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            
            if type == "file",
               let fileData = value as? Data,
               let filename = param["filename"] as? String,
               let mimeType = param["mimeType"] as? String {
                
                body.append("Content-Disposition: form-data; name=\"\(key)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
                body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
                body.append(fileData)
                body.append("\r\n".data(using: .utf8)!)
                
            } else {
                let stringValue = String(describing: value)
                body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
                body.append("\(stringValue)\r\n".data(using: .utf8)!)
            }
        }
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }
}
