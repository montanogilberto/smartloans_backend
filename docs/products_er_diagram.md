# Products — ER diagram

State after migrations `2026-10-15` → `2026-10-15e`
(`sql/migration_history/migrations/`). Only the product-related tables.

- **Solid line** — foreign key enforced by SQL Server.
- **Dashed line** — relationship by convention only (no FK; the SPs keep it).
- Multi-tenant: every catalog row belongs to one `companyId`.

## 1. Catalog — categories, products, prices, options, description

**Core configuration** (every product type): `productCategories` → `products` →
`productOptions` → `productOptionChoices`, with `measurements` giving each choice
its own size (19 L, 600 ml). **Catalog details** (only when they apply):
`productDetails` (base price, cost), `productsDescription` (pharmaceutical
composition), `productForms` (legacy packing).

```mermaid
erDiagram
    companies ||..o{ productCategories : owns
    companies ||..o{ products : owns

    productCategories ||--o{ productCategories : "parent of (subcategory)"
    productCategories ||--o{ products : classifies

    products ||..o{ productDetails : "base price + cost"
    products ||..o{ productOptions : "has options"
    productOptions ||--o{ productOptionChoices : "has choices"
    measurements ||--o{ productOptionChoices : "unit of the choice size"

    products ||..o{ productsDescription : "active ingredients"
    activeIngredients ||..o{ productsDescription : ""
    measurements ||..o{ productsDescription : "unit (mg, ml)"

    manufactures ||..o{ products : makes
    productForms ||..o{ products : "form / packing"
    productsPackingPresentation ||..o{ productForms : ""
    productsPackingType ||..o{ productForms : ""


    companies {
        int companyId PK
        varchar name
    }
    productCategories {
        int productCategoryId PK
        varchar name
        varchar image
        int companyId FK
        int parentCategoryId FK "NULL = top level"
    }
    products {
        int productId PK
        nvarchar name
        varchar code "auto: MAX+1 per company"
        varchar barCode
        varchar description
        date dateOfExpire
        int productCategoryId FK
        int companyId FK
        int productFormId FK
        int manufactureId FK
        bit isSupply "1 = internal use, hidden in POS"
        bit trackInventory "1 = stock is decremented"
        bit isActive "0 = hidden in POS"
        decimal netContent
        varchar unitOfMeasure
        decimal referencePrice "competitor price"
    }
    productDetails {
        int productDetailId PK
        int productId FK
        decimal salePrice "base price"
        decimal unitPrice "cost"
        int stockQuantity "FROZEN since 15c"
    }
    productOptions {
        int productOptionId PK
        int productId FK
        nvarchar optionKey
        nvarchar name "Ciclo, Tamano"
        nvarchar type "radio = one, checkbox = many"
        bit isRequired
    }
    productOptionChoices {
        int productOptionChoiceId PK
        int productOptionId FK
        nvarchar choiceKey
        nvarchar name "Basico, 19 lts, Mango"
        decimal price "added to the base price"
        varchar description
        decimal quantity "19, 600 (NULL for services)"
        int measurementId FK "L, ml (NULL for services)"
    }
    productsDescription {
        int productDescriptionId PK
        int productId FK
        int activeIngredientId FK
        varchar Dosage "325"
        int measurementId FK
        varchar is_principal
    }
    activeIngredients {
        int activeIngredientId PK
        varchar name
        varchar is_principal
    }
    measurements {
        int measurementId PK
        varchar name "liters"
        varchar prefix "UQ: mg, g, kg, ml, L, pz"
    }
    manufactures {
        int manufactureId PK
        varchar name
    }
    productForms {
        int productFormId PK
        varchar quantity "24"
        int productPackingPresentationId FK
        int productsPackingTypeId FK
    }
    productsPackingPresentation {
        int productPackingPresentationId PK
        varchar name "tablets"
    }
    productsPackingType {
        int productsPackingTypeId PK
        varchar name "box"
    }
```

**Price of a sold line** = `productDetails.salePrice` (base) + Σ chosen
`productOptionChoices.price` × quantity. Example: Servicio de lavado, base $0 +
Básico $40 = **$40**.

How the examples map (choice-level size):

| Category | Product | Option | Choice | quantity | unit | price |
|---|---|---|---|---|---|---|
| Bebidas | Garrafón | Tamaño | 19 lts | 19 | L | $10 |
| Bebidas | Garrafón | Tamaño | 10 lts | 10 | L | $5 |
| Bebidas | Té Arizona | Sabor | Mango | 450 | ml | $15 |
| Servicios | Servicio de lavado | Ciclo | Básico | — | — | $40 |

A choice is a variant **without its own stock or barcode**. If a size has to be
counted in inventory or scanned at the register, it must be its own product
(own `inventoryStock` row, own `barCode`).

## 2. Inventory, sales and purchases

```mermaid
erDiagram
    companies ||--o{ Suppliers : has
    Suppliers ||..o{ expenses : "sells to us"

    products ||..o| inventoryStock : "balance per company"
    products ||..o{ inventoryMovements : "ledger"

    income ||--o{ incomeDetails : "lines (cascade delete)"
    products ||..o{ incomeDetails : sold
    incomeDetails ||..o{ incomeDetailOptions : "chosen options"
    productOptionChoices ||..o{ incomeDetailOptions : ""

    expenses ||--o{ expenseDetails : "lines (cascade delete)"
    products ||..o{ expenseDetails : bought
    expenseDetails ||..o{ expenseDetailOptions : "chosen options"
    productOptionChoices ||..o{ expenseDetailOptions : ""

    incomeDetails ||..o{ inventoryMovements : "trigger: sale / sale_reversal"
    expenseDetails ||..o{ inventoryMovements : "trigger: purchase / purchase_reversal"

    products {
        int productId PK
        nvarchar name
        int companyId FK
        bit trackInventory
        bit isSupply
        bit isActive
    }
    productOptionChoices {
        int productOptionChoiceId PK
        int productOptionId FK
        decimal price
    }
    inventoryStock {
        bigint inventoryStockId PK
        int companyId "UQ with productId"
        int productId FK
        decimal stockQuantity "THE stock"
        decimal minStockQty
        decimal reorderQty
    }
    inventoryMovements {
        bigint movementId PK
        int companyId
        int productId FK
        decimal quantityDelta "+ in, - out"
        varchar reason "opening, adjustment, sale, purchase, *_reversal"
        varchar refType "income, expense, product_save, productDetails"
        int refId
        int userId
        datetime2 createdAt
    }
    income {
        int incomeId PK
        int companyId FK
        int clientId FK
        int userId FK
        decimal total
        varchar paymentMethod
        datetime paymentDate
        decimal discountAmount
    }
    incomeDetails {
        int incomeDetailId PK
        int incomeId FK
        int productId FK
        int quantity
        nvarchar piecesJson
    }
    incomeDetailOptions {
        int incomeDetailOptionId PK
        int incomeDetailId FK
        int productOptionId FK
        int productOptionChoiceId FK
        int quantity
    }
    expenses {
        int expenseId PK
        int companyId FK
        int supplierId FK
        int userId FK
        decimal total
        varchar paymentMethod
        varchar expenseType "inventory, general, payroll"
    }
    expenseDetails {
        int expenseDetailId PK
        int expenseId FK
        int productId FK
        decimal quantity
        decimal unitCost
    }
    expenseDetailOptions {
        int expenseDetailOptionId PK
        int expenseDetailId FK
        int productOptionId FK
        int productOptionChoiceId FK
    }
    Suppliers {
        int supplierId PK
        int companyId FK
        nvarchar supplierName
    }
    companies {
        int companyId PK
        varchar name
    }
```

**Stock rule (phase 1):** `inventoryStock.stockQuantity` is the only stock and
always equals Σ `inventoryMovements.quantityDelta`. Sales and purchases post
movements automatically through `trg_incomeDetails_inventory` /
`trg_expenseDetails_inventory`, only for products with `trackInventory = 1`.

## Notes / known debt

| Item | Status |
|---|---|
| `productDetails.stockQuantity` | Frozen since 15c; read stock from `inventoryStock`. |
| `productDetails` | Several rows per product exist (22 rows / 19 products); SPs use the first by `productDetailId`. |
| `productForms`, `productsPacking*` | Legacy pharmacy packing (1 row each). Not used by the POS. |
| `categories`, `subCategories` | Legacy pharmacy tables, **not part of this model** (left out of the diagram). Subcategories live in `productCategories.parentCategoryId`. |
| `one_products` | Reads non-existent `product_details` / `product_options` tables — dead SP. |
| `products.netContent` / `unitOfMeasure` | Size of the base product itself (free-text unit). Kept; candidates to become `measurementId` once validated against the choices. |
| `productForms` direction | Stays `products.productFormId → productForms` (many products share one form); not flipped to `productForm.productId`. |
| Dashed relationships | No FK in SQL Server; adding FKs is a candidate follow-up once data is verified clean. |
