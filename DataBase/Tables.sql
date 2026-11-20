

CREATE TABLE dbo.Users (
    UserID INT IDENTITY(1,1) NOT NULL,
    Username NVARCHAR(20) NOT NULL,
    Email NVARCHAR(254) NOT NULL,
    PasswordHash NVARCHAR(255) NOT NULL,
    CreatedAt DATETIMEOFFSET(0) NOT NULL
        CONSTRAINT DF_Users_CreatedAt DEFAULT SYSDATETIMEOFFSET(),
    IsRemoved BIT NOT NULL
        CONSTRAINT DF_Users_IsRemoved DEFAULT (0),
    CONSTRAINT PK_Users PRIMARY KEY (UserID),
    CONSTRAINT UQ_Users_Username UNIQUE (Username),
    CONSTRAINT UQ_Users_Email UNIQUE (Email)
);
GO

CREATE TABLE dbo.StoreGames (
    GameID INT IDENTITY(1,1) NOT NULL,
    SourceGameID NVARCHAR(100) NULL,
    Title NVARCHAR(200) NOT NULL,
    Price DECIMAL(10,2) NOT NULL,
    ReleaseDate DATE NULL,
    IsRemoved BIT NOT NULL
        CONSTRAINT DF_StoreGames_IsRemoved DEFAULT (0),
    CONSTRAINT PK_StoreGames PRIMARY KEY (GameID),
    CONSTRAINT CK_StoreGames_Price CHECK (Price >= 0)
);
GO


CREATE UNIQUE INDEX UX_StoreGames_SourceGameID
    ON dbo.StoreGames (SourceGameID)
    WHERE SourceGameID IS NOT NULL;
GO

CREATE TABLE dbo.Genre (
    GenreID INT IDENTITY(1,1) NOT NULL,
    GenreName NVARCHAR(50) NOT NULL,
    CONSTRAINT PK_Genre PRIMARY KEY (GenreID),
    CONSTRAINT UQ_Genre_GenreName UNIQUE (GenreName)
);
GO

CREATE TABLE dbo.TransactionTypes (
    TransactionTypeID TINYINT NOT NULL,
    TypeName NVARCHAR(20) NOT NULL,
    BalanceEffect SMALLINT NOT NULL,
    CONSTRAINT PK_TransactionTypes PRIMARY KEY (TransactionTypeID),
    CONSTRAINT UQ_TransactionTypes_TypeName UNIQUE (TypeName),
    CONSTRAINT CK_TransactionTypes_BalanceEffect CHECK (BalanceEffect IN (-1, 1))
);
GO

CREATE TABLE dbo.GameGenres (
    GameID INT NOT NULL,
    GenreID INT NOT NULL,
    CONSTRAINT PK_GameGenres PRIMARY KEY (GameID, GenreID),
    CONSTRAINT FK_GameGenres_StoreGames
        FOREIGN KEY (GameID) REFERENCES dbo.StoreGames (GameID),
    CONSTRAINT FK_GameGenres_Genre
        FOREIGN KEY (GenreID) REFERENCES dbo.Genre (GenreID)
);
GO

CREATE TABLE dbo.Purchases (
    PurchaseID INT IDENTITY(1,1) NOT NULL,
    UserID INT NOT NULL,
    PurchaseTime DATETIMEOFFSET(0) NOT NULL
        CONSTRAINT DF_Purchases_PurchaseTime DEFAULT SYSDATETIMEOFFSET(),
    CONSTRAINT PK_Purchases PRIMARY KEY (PurchaseID),
    CONSTRAINT FK_Purchases_Users
        FOREIGN KEY (UserID) REFERENCES dbo.Users (UserID),
    CONSTRAINT UQ_Purchases_PurchaseID_UserID UNIQUE (PurchaseID, UserID)
);
GO

CREATE TABLE dbo.PurchaseItems (
    PurchaseItemID INT IDENTITY(1,1) NOT NULL,
    PurchaseID INT NOT NULL,
    GameID INT NOT NULL,
    PriceAtPurchase DECIMAL(10,2) NOT NULL,
    CONSTRAINT PK_PurchaseItems PRIMARY KEY (PurchaseItemID),
    CONSTRAINT FK_PurchaseItems_Purchases
        FOREIGN KEY (PurchaseID) REFERENCES dbo.Purchases (PurchaseID),
    CONSTRAINT FK_PurchaseItems_StoreGames
        FOREIGN KEY (GameID) REFERENCES dbo.StoreGames (GameID),
    CONSTRAINT UQ_PurchaseItems_PurchaseID_GameID UNIQUE (PurchaseID, GameID),
    CONSTRAINT CK_PurchaseItems_PriceAtPurchase CHECK (PriceAtPurchase >= 0)
);
GO

CREATE TABLE dbo.UsersTransactions (
    UserTransactionID INT IDENTITY(1,1) NOT NULL,
    UserID INT NOT NULL,
    PurchaseID INT NULL,
    TransactionTypeID TINYINT NOT NULL,
    Amount DECIMAL(10,2) NOT NULL,
    TransactionDate DATETIMEOFFSET(0) NOT NULL
        CONSTRAINT DF_UsersTransactions_TransactionDate DEFAULT SYSDATETIMEOFFSET(),
    CONSTRAINT PK_UsersTransactions PRIMARY KEY (UserTransactionID),
    CONSTRAINT FK_UsersTransactions_Users
        FOREIGN KEY (UserID) REFERENCES dbo.Users (UserID),
   
    CONSTRAINT FK_UsersTransactions_PurchaseOwner
        FOREIGN KEY (PurchaseID, UserID)
        REFERENCES dbo.Purchases (PurchaseID, UserID),
    CONSTRAINT FK_UsersTransactions_TransactionTypes
        FOREIGN KEY (TransactionTypeID)
        REFERENCES dbo.TransactionTypes (TransactionTypeID),
    CONSTRAINT CK_UsersTransactions_Amount CHECK (Amount > 0),
    CONSTRAINT CK_UsersTransactions_PurchaseReference CHECK (
        (TransactionTypeID = 1 AND PurchaseID IS NULL)
        OR (TransactionTypeID IN (2, 3) AND PurchaseID IS NOT NULL)
    )
);
GO

CREATE TABLE dbo.LibraryItems (
    LibraryItemID INT IDENTITY(1,1) NOT NULL,
    UserID INT NOT NULL,
    GameID INT NOT NULL,
    DateAdded DATETIMEOFFSET(0) NOT NULL
        CONSTRAINT DF_LibraryItems_DateAdded DEFAULT SYSDATETIMEOFFSET(),
    PlaytimeMinutes INT NOT NULL
        CONSTRAINT DF_LibraryItems_PlaytimeMinutes DEFAULT (0),
    CONSTRAINT PK_LibraryItems PRIMARY KEY (LibraryItemID),
    CONSTRAINT FK_LibraryItems_Users
        FOREIGN KEY (UserID) REFERENCES dbo.Users (UserID),
    CONSTRAINT FK_LibraryItems_StoreGames
        FOREIGN KEY (GameID) REFERENCES dbo.StoreGames (GameID),
    CONSTRAINT UQ_LibraryItems_UserID_GameID UNIQUE (UserID, GameID),
    CONSTRAINT CK_LibraryItems_PlaytimeMinutes CHECK (PlaytimeMinutes >= 0)
);
GO

CREATE TABLE dbo.Reviews (
    ReviewID INT IDENTITY(1,1) NOT NULL,
    LibraryItemID INT NOT NULL,
    ReviewDate DATETIMEOFFSET(0) NOT NULL
        CONSTRAINT DF_Reviews_ReviewDate DEFAULT SYSDATETIMEOFFSET(),
    ReviewText NVARCHAR(MAX) NULL,
    Rating TINYINT NOT NULL,
    CONSTRAINT PK_Reviews PRIMARY KEY (ReviewID),
    CONSTRAINT UQ_Reviews_LibraryItemID UNIQUE (LibraryItemID),
    CONSTRAINT FK_Reviews_LibraryItems
        FOREIGN KEY (LibraryItemID) REFERENCES dbo.LibraryItems (LibraryItemID),
    CONSTRAINT CK_Reviews_Rating CHECK (Rating BETWEEN 1 AND 5)
);
GO
