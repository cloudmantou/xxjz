import Foundation
import UIKit

struct ReceiptAnalysis {
    var merchant: String
    var total: Double
    var date: Date
    var items: [String]
}

protocol AIAnalysisServiceProtocol: AnyObject {
    func analyzeReceipt(image: UIImage) async throws -> ReceiptAnalysis
    func suggestCategory(itemName: String) async throws -> String
}

// MARK: - Mock AI Analysis Service

final class MockAIAnalysisService: AIAnalysisServiceProtocol {

    static let shared = MockAIAnalysisService()

    private init() {}

    func analyzeReceipt(image: UIImage) async throws -> ReceiptAnalysis {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 1_500_000_000)

        // Return mock analysis
        return ReceiptAnalysis(
            merchant: "京东商城",
            total: 9999.00,
            date: Date(),
            items: ["iPhone 15 Pro Max 256GB"]
        )
    }

    func suggestCategory(itemName: String) async throws -> String {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 500_000_000)

        // Simple keyword-based category suggestion
        let keywords: [String: String] = [
            "iPhone": "电子产品",
            "iPad": "电子产品",
            "Mac": "电子产品",
            "AirPods": "数码配件",
            "Apple Watch": "电子产品",
            "手机": "电子产品",
            "电脑": "电子产品",
            "相机": "电子产品",
            "电视": "电子产品",
            "冰箱": "家居用品",
            "洗衣机": "家居用品",
            "空调": "家居用品",
            "沙发": "家居用品",
            "床": "家居用品",
            "衣柜": "家居用品"
        ]

        for (keyword, category) in keywords {
            if itemName.contains(keyword) {
                return category
            }
        }

        return "其他"
    }
}

// MARK: - Production AI Analysis Service (Placeholder)

final class ProductionAIAnalysisService: AIAnalysisServiceProtocol {

    static let shared = ProductionAIAnalysisService()

    private init() {}

    func analyzeReceipt(image: UIImage) async throws -> ReceiptAnalysis {
        // TODO: Implement actual AI analysis using Core ML or cloud service
        throw AIAnalysisError.notImplemented
    }

    func suggestCategory(itemName: String) async throws -> String {
        // TODO: Implement actual AI category suggestion
        throw AIAnalysisError.notImplemented
    }
}

enum AIAnalysisError: LocalizedError {
    case notImplemented
    case serviceUnavailable
    case invalidInput

    var errorDescription: String? {
        switch self {
        case .notImplemented:
            return "AI分析功能正在开发中"
        case .serviceUnavailable:
            return "AI服务暂时不可用"
        case .invalidInput:
            return "输入数据无效"
        }
    }
}
