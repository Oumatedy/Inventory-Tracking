-- Inventory Management System Database

-- Create Database
CREATE DATABASE IF NOT EXISTS InventoryDB;
USE InventoryDB;

-- =============================================
-- Table Structure with Enhanced Constraints
-- =============================================

-- Employees Table
CREATE TABLE Employees (
    EmployeeID INT PRIMARY KEY AUTO_INCREMENT,
    EmployeeName VARCHAR(100) NOT NULL,
    Position ENUM('Manager', 'Supervisor', 'Clerk') NOT NULL,
    HireDate DATE NOT NULL,
    Salary DECIMAL(10, 2) CHECK (Salary > 0),
    INDEX idx_position (Position)
) ENGINE=InnoDB;

-- Suppliers Table
CREATE TABLE Suppliers (
    SupplierID INT PRIMARY KEY AUTO_INCREMENT,
    SupplierName VARCHAR(100) NOT NULL UNIQUE,
    ContactEmail VARCHAR(100) NOT NULL,
    Phone VARCHAR(15) NOT NULL,
    INDEX idx_supplier_name (SupplierName)
) ENGINE=InnoDB;

-- Categories Table
CREATE TABLE Categories (
    CategoryID INT PRIMARY KEY AUTO_INCREMENT,
    CategoryName VARCHAR(100) NOT NULL UNIQUE,
    ParentCategoryID INT NULL,
    FOREIGN KEY (ParentCategoryID) REFERENCES Categories(CategoryID)
) ENGINE=InnoDB;

-- Products Table with Enhanced Constraints
CREATE TABLE Products (
    ProductID INT PRIMARY KEY AUTO_INCREMENT,
    ProductName VARCHAR(100) NOT NULL,
    SKU VARCHAR(50) UNIQUE NOT NULL,
    Price DECIMAL(10, 2) CHECK (Price > 0),
    Cost DECIMAL(10, 2) CHECK (Cost > 0),
    SupplierID INT NOT NULL,
    CategoryID INT NOT NULL,
    StockQuantity INT DEFAULT 0 CHECK (StockQuantity >= 0),
    LastRestocked DATE,
    FOREIGN KEY (SupplierID) REFERENCES Suppliers(SupplierID) ON DELETE RESTRICT,
    FOREIGN KEY (CategoryID) REFERENCES Categories(CategoryID) ON DELETE RESTRICT,
    INDEX idx_product_name (ProductName),
    INDEX idx_sku (SKU)
) ENGINE=InnoDB;

-- Customers Table with Normalized Addresses
CREATE TABLE Customers (
    CustomerID INT PRIMARY KEY AUTO_INCREMENT,
    CustomerName VARCHAR(100) NOT NULL,
    Email VARCHAR(100) UNIQUE NOT NULL,
    Phone VARCHAR(15) NOT NULL,
    INDEX idx_customer_email (Email)
) ENGINE=InnoDB;

CREATE TABLE Addresses (
    AddressID INT PRIMARY KEY AUTO_INCREMENT,
    CustomerID INT NOT NULL,
    AddressType ENUM('Billing', 'Shipping') NOT NULL,
    Street VARCHAR(255) NOT NULL,
    City VARCHAR(100) NOT NULL,
    State VARCHAR(50) NOT NULL,
    ZipCode VARCHAR(20) NOT NULL,
    FOREIGN KEY (CustomerID) REFERENCES Customers(CustomerID) ON DELETE CASCADE,
    INDEX idx_address_type (AddressType)
) ENGINE=InnoDB;

-- Orders Table with Status Constraints
CREATE TABLE Orders (
    OrderID INT PRIMARY KEY AUTO_INCREMENT,
    OrderDate DATETIME DEFAULT CURRENT_TIMESTAMP,
    CustomerID INT NOT NULL,
    ShippingAddressID INT NOT NULL,
    OrderStatus ENUM('Pending', 'Processing', 'Shipped', 'Delivered', 'Canceled') DEFAULT 'Pending',
    FOREIGN KEY (CustomerID) REFERENCES Customers(CustomerID) ON DELETE RESTRICT,
    FOREIGN KEY (ShippingAddressID) REFERENCES Addresses(AddressID),
    INDEX idx_order_date (OrderDate),
    INDEX idx_order_status (OrderStatus)
) ENGINE=InnoDB;

-- Order Details Table with Quantity Check
CREATE TABLE OrderDetails (
    OrderDetailID INT PRIMARY KEY AUTO_INCREMENT,
    OrderID INT NOT NULL,
    ProductID INT NOT NULL,
    Quantity INT NOT NULL CHECK (Quantity > 0),
    UnitPrice DECIMAL(10, 2) NOT NULL,
    FOREIGN KEY (OrderID) REFERENCES Orders(OrderID) ON DELETE CASCADE,
    FOREIGN KEY (ProductID) REFERENCES Products(ProductID) ON DELETE RESTRICT,
    INDEX idx_order_product (OrderID, ProductID)
) ENGINE=InnoDB;

-- Payments Table with Financial Constraints
CREATE TABLE Payments (
    PaymentID INT PRIMARY KEY AUTO_INCREMENT,
    OrderID INT NOT NULL,
    PaymentDate DATETIME DEFAULT CURRENT_TIMESTAMP,
    PaymentMethod ENUM('Credit Card', 'PayPal', 'Bank Transfer') NOT NULL,
    Amount DECIMAL(10, 2) CHECK (Amount > 0),
    PaymentStatus ENUM('Pending', 'Completed', 'Failed', 'Refunded') DEFAULT 'Pending',
    FOREIGN KEY (OrderID) REFERENCES Orders(OrderID) ON DELETE RESTRICT,
    INDEX idx_payment_date (PaymentDate)
) ENGINE=InnoDB;

-- Inventory Management Extensions
CREATE TABLE StockAlerts (
    AlertID INT PRIMARY KEY AUTO_INCREMENT,
    ProductID INT NOT NULL,
    AlertDate DATETIME DEFAULT CURRENT_TIMESTAMP,
    Message TEXT NOT NULL,
    FOREIGN KEY (ProductID) REFERENCES Products(ProductID) ON DELETE CASCADE
) ENGINE=InnoDB;

-- =============================================
-- Business Logic Implementation
-- =============================================

-- Trigger: Update Stock After Order
DELIMITER $$
CREATE TRIGGER UpdateStockAfterOrder
AFTER INSERT ON OrderDetails
FOR EACH ROW
BEGIN
    UPDATE Products 
    SET StockQuantity = StockQuantity - NEW.Quantity
    WHERE ProductID = NEW.ProductID;
END$$
DELIMITER ;

-- Trigger: Prevent Negative Stock
DELIMITER $$
CREATE TRIGGER PreventNegativeStock
BEFORE UPDATE ON Products
FOR EACH ROW
BEGIN
    IF NEW.StockQuantity < 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Stock quantity cannot be negative';
    END IF;
END$$
DELIMITER ;

-- Trigger: Generate Low Stock Alert
DELIMITER $$
CREATE TRIGGER GenerateLowStockAlert
AFTER UPDATE ON Products
FOR EACH ROW
BEGIN
    IF NEW.StockQuantity < 10 THEN
        INSERT INTO StockAlerts (ProductID, Message)
        VALUES (NEW.ProductID, 
                CONCAT('Low stock alert: Only ', NEW.StockQuantity, ' units remaining'));
    END IF;
END$$
DELIMITER ;

-- View: Sales Summary
CREATE VIEW SalesSummary AS
SELECT 
    o.OrderID,
    o.OrderDate,
    c.CustomerName,
    SUM(od.Quantity * od.UnitPrice) AS TotalSales,
    pym.PaymentMethod,
    pym.PaymentStatus
FROM Orders o
JOIN OrderDetails od USING (OrderID)
JOIN Customers c USING (CustomerID)
LEFT JOIN Payments pym USING (OrderID)
GROUP BY o.OrderID;

-- Stored Procedure: Place New Order
DELIMITER $$
CREATE PROCEDURE PlaceOrder(
    IN pCustomerID INT,
    IN pShippingAddressID INT,
    IN pProductID INT,
    IN pQuantity INT
)
BEGIN
    DECLARE productPrice DECIMAL(10,2);
    
    START TRANSACTION;
    
    -- Get product price
    SELECT Price INTO productPrice 
    FROM Products 
    WHERE ProductID = pProductID
    FOR UPDATE;
    
    -- Create order
    INSERT INTO Orders (CustomerID, ShippingAddressID)
    VALUES (pCustomerID, pShippingAddressID);
    
    SET @newOrderID = LAST_INSERT_ID();
    
    -- Add order details
    INSERT INTO OrderDetails (OrderID, ProductID, Quantity, UnitPrice)
    VALUES (@newOrderID, pProductID, pQuantity, productPrice);
    
    -- Create invoice
    INSERT INTO Payments (OrderID, PaymentMethod, Amount)
    VALUES (@newOrderID, 'Credit Card', pQuantity * productPrice);
    
    COMMIT;
END$$
DELIMITER ;

-- =============================================
-- Sample Data Insertion
-- =============================================

-- Insert Suppliers
INSERT INTO Suppliers (SupplierName, ContactEmail, Phone) VALUES
('Tech Supplies Inc', 'sales@techsupplies.com', '555-1234'),
('Office World', 'orders@officeworld.com', '555-5678');

-- Insert Categories
INSERT INTO Categories (CategoryName) VALUES
('Electronics'),
('Office Furniture'),
('Computer Accessories');

-- Insert Products
INSERT INTO Products (ProductName, SKU, Price, Cost, SupplierID, CategoryID, StockQuantity) VALUES
('Ergonomic Office Chair', 'CHAIR-2025', 199.99, 120.00, 2, 2, 50),
('Wireless Keyboard', 'KB-WL-2025', 49.99, 25.00, 1, 3, 100);

-- Insert Customers
INSERT INTO Customers (CustomerName, Email, Phone) VALUES
('John Smith', 'john.smith@example.com', '555-1111'),
('Acme Corporation', 'purchasing@acme.com', '555-2222');

-- Insert Addresses
INSERT INTO Addresses (CustomerID, AddressType, Street, City, State, ZipCode) VALUES
(1, 'Shipping', '123 Main St', 'New York', 'NY', '10001'),
(2, 'Shipping', '456 Business Ave', 'Chicago', 'IL', '60601');

-- =============================================
-- Database Documentation
-- =============================================

/*
ERD Relationships:
1. Customers 1:M Orders
2. Orders 1:M OrderDetails
3. Products 1:M OrderDetails
4. Suppliers 1:M Products
5. Categories 1:M Products
6. Orders 1:1 Payments
7. Customers 1:M Addresses

Key Features:
- Automatic stock management via triggers
- Financial data integrity checks
- Normalized address system
- Comprehensive sales reporting view
- ACID-compliant order placement procedure
- Real-time stock alerts
*/

