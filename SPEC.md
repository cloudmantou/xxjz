# AssetLife - iOS App Specification

## 1. Project Overview

- **Project Name**: AssetLife
- **Bundle Identifier**: com.assetlife.app
- **Core Functionality**: Personal asset management and wishlist tracking app with financial analytics
- **Target Users**: Individuals tracking personal assets, investments, and purchase wishlists
- **iOS Version Support**: iOS 17.0+
- **Architecture**: MVVM (Model-View-ViewModel)
- **UI Framework**: SwiftUI
- **Data Framework**: SwiftData

## 2. UI/UX Specification

### Screen Structure

```
TabView
├── HomeTab (Dashboard)
│   └── DashboardView
│       ├── TotalAssetCard
│       ├── StatusDistributionChart
│       ├── CategoryDistributionChart
│       ├── TopDailyCostChart
│       └── MonthlyTrendChart
├── AssetTab
│   ├── AssetListView
│   ├── AssetDetailView
│   ├── AssetFormView (Add/Edit)
│   ├── ExtraCostFormView
│   └── SaleRecordFormView
├── WishTab
│   ├── WishlistView
│   ├── WishlistDetailView
│   ├── WishlistFormView (Add/Edit)
│   ├── PlatformPriceFormView
│   └── PriceHistoryFormView
└── ProfileTab
    └── ProfileView
```

### Visual Design

#### Color Palette
- **Primary**: #007AFF (iOS Blue)
- **Secondary**: #5856D6 (Purple)
- **Accent**: #34C759 (Green - Profit)
- **Warning**: #FF9500 (Orange)
- **Danger**: #FF3B30 (Red - Loss)
- **Background**: System Background (adaptive)
- **Secondary Background**: #F2F2F7 / #1C1C1E (adaptive)
- **Text Primary**: #000000 / #FFFFFF (adaptive)
- **Text Secondary**: #8E8E93 (adaptive)

#### Typography
- **Large Title**: 34pt, Bold
- **Title 1**: 28pt, Bold
- **Title 2**: 22pt, Bold
- **Title 3**: 20pt, Semibold
- **Headline**: 17pt, Semibold
- **Body**: 17pt, Regular
- **Callout**: 16pt, Regular
- **Subheadline**: 15pt, Regular
- **Footnote**: 13pt, Regular
- **Caption**: 12pt, Regular

#### Spacing System (8pt Grid)
- **xs**: 4pt
- **sm**: 8pt
- **md**: 16pt
- **lg**: 24pt
- **xl**: 32pt

### Views & Components

#### Common Components
- AssetCard: Displays asset summary (name, value, daily cost, status)
- WishCard: Displays wishlist item (name, current price, target price)
- StatCard: Statistics display card with icon, title, value
- ChartCard: Container for Swift Charts
- FormTextField: Styled text input
- FormPicker: Styled picker selection
- FormDatePicker: Date selection
- FormCurrencyField: Currency input
- EmptyStateView: Empty state placeholder
- LoadingView: Loading indicator

## 3. Data Models

### AssetItem
| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Unique identifier |
| name | String | Asset name |
| category | String | Category (electronics, furniture, vehicle, etc.) |
| purchaseDate | Date | Purchase date |
| purchasePrice | Double | Original purchase price |
| currentValue | Double | Current estimated value |
| status | AssetStatus | active, sold, disposed |
| notes | String? | Optional notes |
| imageData | Data? | Optional image |
| createdAt | Date | Creation timestamp |
| updatedAt | Date | Last update timestamp |
| extraCosts | [AssetExtraCost] | Related extra costs |
| saleRecords | [AssetSaleRecord] | Related sale records |

### AssetExtraCost
| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Unique identifier |
| assetId | UUID | Parent asset reference |
| costType | String | Type (repair, upgrade, insurance, etc.) |
| amount | Double | Cost amount |
| date | Date | Cost date |
| notes | String? | Optional notes |
| createdAt | Date | Creation timestamp |

### AssetSaleRecord
| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Unique identifier |
| assetId | UUID | Parent asset reference |
| saleDate | Date | Sale date |
| salePrice | Double | Sale price |
| platform | String? | Sale platform |
| notes | String? | Optional notes |
| createdAt | Date | Creation timestamp |

### WishlistItem
| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Unique identifier |
| name | String | Item name |
| category | String | Category |
| targetPrice | Double | Target purchase price |
| priority | Int | Priority (1-5) |
| notes | String? | Optional notes |
| imageData | Data? | Optional image |
| isPurchased | Bool | Whether purchased |
| createdAt | Date | Creation timestamp |
| updatedAt | Date | Last update timestamp |
| platformPrices | [WishlistPlatformPrice] | Platform prices |
| priceHistories | [WishlistPriceHistory] | Price histories |

### WishlistPlatformPrice
| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Unique identifier |
| wishlistItemId | UUID | Parent wishlist reference |
| platform | String | Platform name |
| price | Double | Current price |
| url | String? | Product URL |
| lastUpdated | Date | Last update timestamp |

### WishlistPriceHistory
| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Unique identifier |
| wishlistItemId | UUID | Parent wishlist reference |
| price | Double | Price at record time |
| recordedAt | Date | Record timestamp |

## 4. Functionality Specification

### Tab Structure

#### Home Tab (Dashboard)
- Total asset value display
- Asset status distribution (pie chart)
- Asset category distribution (pie chart)
- Top 5 daily cost assets (bar chart)
- Monthly spending trend (line chart)

#### Asset Tab
- Asset list with search and filter
- Add new asset
- Edit existing asset
- Asset detail with:
  - Basic info
  - Extra costs list
  - Sale records list
  - Lifecycle progress
- Add/Edit extra cost
- Add/Edit sale record

#### Wish Tab
- Wishlist with search and sort
- Add new wishlist item
- Edit existing wishlist item
- Wishlist detail with:
  - Basic info
  - Platform prices
  - Price history chart
- Add/Edit platform price
- Add price history entry

#### Profile Tab
- User profile display
- App settings
- Statistics summary

### Calculation Services

#### CalculationService
- `holdingDays(from:purchaseDate)` -> Int
- `dailyCost(purchasePrice:totalCosts:holdingDays)` -> Double
- `lifecycleProgress(purchaseDate:expectedLifeYears)` -> Double
- `saleProfitLoss(purchasePrice:totalCosts:salePrice)` -> Double
- `priceChangePercent(current:previous)` -> Double
- `averagePrice(prices:[])` -> Double
- `lowestPrice(prices:[])` -> Double
- `highestPrice(prices:[])` -> Double

### Services (Protocol + Mock)

#### OCRService Protocol
```swift
protocol OCRService {
    func recognizeText(from image: UIImage) async throws -> String
}
```

#### AIAnalysisService Protocol
```swift
protocol AIAnalysisService {
    func analyzeReceipt(image: UIImage) async throws -> ReceiptAnalysis
    func suggestCategory(itemName: String) async throws -> String
}

struct ReceiptAnalysis {
    var merchant: String
    var total: Double
    var date: Date
    var items: [String]
}
```

## 5. Technical Specification

### Dependencies
- Swift Charts (built-in iOS 16+)
- SwiftData (built-in iOS 17+)
- SwiftUI (built-in)

### Project Structure
```
AssetLife/
├── App/
│   └── AssetLifeApp.swift
├── Models/
│   ├── AssetItem.swift
│   ├── AssetExtraCost.swift
│   ├── AssetSaleRecord.swift
│   ├── WishlistItem.swift
│   ├── WishlistPlatformPrice.swift
│   └── WishlistPriceHistory.swift
├── ViewModels/
│   ├── DashboardViewModel.swift
│   ├── AssetViewModel.swift
│   └── WishlistViewModel.swift
├── Views/
│   ├── Home/
│   │   └── DashboardView.swift
│   ├── Asset/
│   │   ├── AssetListView.swift
│   │   ├── AssetDetailView.swift
│   │   ├── AssetFormView.swift
│   │   ├── ExtraCostFormView.swift
│   │   └── SaleRecordFormView.swift
│   ├── Wish/
│   │   ├── WishlistView.swift
│   │   ├── WishlistDetailView.swift
│   │   ├── WishlistFormView.swift
│   │   ├── PlatformPriceFormView.swift
│   │   └── PriceHistoryFormView.swift
│   ├── Profile/
│   │   └── ProfileView.swift
│   ├── Components/
│   │   ├── AssetCard.swift
│   │   ├── WishCard.swift
│   │   ├── StatCard.swift
│   │   ├── ChartCard.swift
│   │   └── EmptyStateView.swift
│   └── MainTabView.swift
├── Services/
│   ├── CalculationService.swift
│   ├── OCRService.swift
│   └── AIAnalysisService.swift
├── Extensions/
│   ├── Color+Theme.swift
│   ├── Date+Extensions.swift
│   └── Double+Currency.swift
├── Utilities/
│   └── Constants.swift
└── Resources/
    └── Assets.xcassets
```

### Dark Mode
- Full support using SwiftUI adaptive colors
- System semantic colors used throughout

## 6. Testing

### Unit Tests
- CalculationService tests
- Model initialization tests
- ViewModel logic tests
