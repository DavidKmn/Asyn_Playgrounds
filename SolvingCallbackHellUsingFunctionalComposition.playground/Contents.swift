import UIKit

infix operator ~>: MultiplicationPrecedence
typealias CompletionHandler<Result> = (Result?, Error?) -> Void

func ~> <T, U>(_ first: @escaping (CompletionHandler<T>) -> Void, _ second: @escaping (T, CompletionHandler<U>) -> Void) -> (CompletionHandler<U>) -> Void {
    return { completion in
        first({ firstResult, error in
            guard let firstResult = firstResult else { completion(nil, error); return }
            
            second(firstResult, { (secondResult, error) in
                completion(secondResult, error)
            })
        })
    }
}

func ~> <T, U>(_ first: @escaping (CompletionHandler<T>) -> Void, _ transform: @escaping (T) -> U) -> (CompletionHandler<U>) -> Void {
    return { completion in
        first({ result, error in
            guard let result = result else { completion(nil, error); return }
            
            completion(transform(result), nil)
        })
    }
}

func asyncFunc1(_ completion: CompletionHandler<Int>) {
    completion(4, nil)
}

func asyncFunc2(arg: Int, _ completion: CompletionHandler<String>) {
    completion("Result: \(arg)", nil)
}

func asyncFunc3(arg: String, _ completion: CompletionHandler<String>) {
    completion("🍒 \(arg) 🍒", nil)
}

let chaingedFuncs = asyncFunc1 ~> asyncFunc2 ~> asyncFunc3

chaingedFuncs({ result, error in
    guard let result = result else { return }
    print(result)
})

let chainedFuncsWithMap = asyncFunc1 ~> { int in return String(int / 2) } ~> asyncFunc3


chainedFuncsWithMap({ result, _ in
    guard let result = result else { return }
    print(result)
})
