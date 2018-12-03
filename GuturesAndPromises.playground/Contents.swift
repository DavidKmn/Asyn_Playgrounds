import UIKit
import PlaygroundSupport

enum Result<Value> {
    case value(Value)
    case error(Error)
}

enum NetworkingError: Error {
    case unknown(message: String)
    case noHTTPResponse
    case badHTTPStatusCode(Int)
    case noDataReturned
}

class Future<Value> {
    fileprivate var result: Result<Value>? {
        didSet { result.map(report)}
    }
    
    private lazy var callbacks = [(Result<Value>) -> Void]()
    
    func observe(with callback: @escaping (Result<Value>) -> Void) {
        callbacks.append(callback)
        // if the result has already been set, call the callback direct
        result.map(callback)
    }
    private func report(result: Result<Value>) {
        callbacks.forEach { $0(result) }
    }
}

class Promise<Value>: Future<Value> {
    init(value: Value? = nil) {
        super.init()
        
        result = value.map(Result.value)
    }
    
    func resolve(with value: Value) {
        result = .value(value)
    }
    
    func reject(with error: Error) {
        result = .error(error)
    }
}

extension Future {
    func chained<NextValue>(with closure: @escaping (Value) throws -> Future<NextValue>) -> Future<NextValue> {
        let promise = Promise<NextValue>()
        
        // observe the current future
        observe { (result) in
            switch result {
            case .value(let value):
                do {
                    // Try to construct a new future given the value from the first name
                    let future = try closure(value)
                    future.observe(with: { (result) in
                        switch result {
                        case .value(let value): promise.resolve(with: value)
                        case .error(let error): promise.reject(with: error)
                        }
                    })
                } catch {
                    promise.reject(with: error)
                }
            case .error(let error):
                promise.reject(with: error)
            }
        }
        
        return promise
    }
}

extension Future where Value: Savable {
    func saved(in database: Database) -> Future<Value> {
        return chained(with: { (user) in
            let promise = Promise<Value>()
            
            database.save(user) {
                promise.resolve(with: user)
            }
            
            return promise
        })
    }
}

extension Future {
    func transformed<NextValue>(with closure: @escaping (Value) throws -> NextValue) -> Future<NextValue> {
        return chained(with: { value in
            return try Promise(value: closure(value))
        })
    }
}

protocol Database {
    func save<T: Savable>(_ item: T, _ completion: @escaping () -> Void)
}

extension URLSession {
    func request(url: URL) -> Future<Data> {
        let promise = Promise<Data>()
        let task = dataTask(with: url) { (data, response, error) in
            guard let httpResponse = response as? HTTPURLResponse else {
                promise.reject(with: NetworkingError.noHTTPResponse)
                return
                }
            
            let statusCode = httpResponse.statusCode
            
            guard (0...400)~=statusCode else {
                promise.reject(with: NetworkingError.badHTTPStatusCode(statusCode))
                return
            }
            
            if let error = error {
                promise.reject(with: NetworkingError.unknown(message: error.localizedDescription))
            } else if let data = data {
                promise.resolve(with: data)
            } else {
                promise.reject(with: NetworkingError.noDataReturned)
            }
        }
        
        task.resume()
        return promise
    }
}

extension Future where Value == Data {
    func decoded<NextValue: Decodable>() -> Future<NextValue> {
        return transformed { (value) in try JSONDecoder().decode(NextValue.self, from: value) }
    }
}

protocol Savable: Encodable {
    var primaryKey: String { get }
}

class FileSystemDatabase: Database {
    func save<T: Savable>(_ item: T, _ completion: @escaping () -> Void) {
        
        let fileManager = FileManager.default
        do {
            let documentDirectory = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor:nil, create:false)
            let fileURL = documentDirectory.appendingPathComponent(item.primaryKey)
            let data = try JSONEncoder().encode(item)
            try data.write(to: fileURL)
            completion()
        } catch {
            print(error)
        }
        
    }
}

class User: Decodable {

    let name: String
    let avatarImageUrl: String
    
    private enum CodingKeys: String, CodingKey {
        case name = "name"
        case avatarImageUrl = "avatarImageUrl"
    }
}

extension User: Savable {
    var primaryKey: String {
        return UUID.init().uuidString
    }
}

class UserLoader {
    let urlSession = URLSession.shared
    let database = FileSystemDatabase()
    
    func loadUser(withId id: Int) -> Future<User> {
        return urlSession.request(url: url(withUserId: id)).decoded().saved(in: database)
    }
    
    func url(withUserId userId: Int) -> URL {
        return URL(string: "https://afternoon-hollows-89943.herokuapp.com/user/\(userId)")!
    }
}


class ViewController: UIViewController {
    
    var users = [User]()
    let cellId = "cellId"
    let userLoader = UserLoader()
    
    override func viewDidLoad() {
        super.viewDidLoad()

        userLoader.loadUser(withId: 1).observe { (result) in
            switch result {
            case .value(let value):
                print(value.name)
                print(value.avatarImageUrl)
            case .error(let error):
                print(error.localizedDescription)
            }
        }
    }
}

let viewController = ViewController()
viewController.preferredContentSize = CGSize(width: 375, height: 812)
PlaygroundPage.current.liveView = viewController

