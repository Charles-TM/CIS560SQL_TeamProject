
CREATE OR ALTER PROCEDURE dbo.RegisterUser
    @Username NVARCHAR(20),
    @Email NVARCHAR(254),
    @PasswordHash NVARCHAR(255),
    @NewUserID INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    IF NULLIF(LTRIM(RTRIM(@Username)), N'') IS NULL
        THROW 50001, 'Username is required.', 1;
    IF NULLIF(LTRIM(RTRIM(@Email)), N'') IS NULL
        THROW 50002, 'Email is required.', 1;
    IF NULLIF(@PasswordHash, N'') IS NULL
        THROW 50003, 'Password hash is required.', 1;

    INSERT INTO dbo.Users (Username, Email, PasswordHash)
    VALUES (@Username, @Email, @PasswordHash);

    SET @NewUserID = CONVERT(INT, SCOPE_IDENTITY());
END;
GO

CREATE OR ALTER PROCEDURE dbo.GetUserProfile
    @UserID INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT UserID, Username, Email, CreatedAt
    FROM dbo.Users
    WHERE UserID = @UserID AND IsRemoved = 0;
END;
GO

CREATE OR ALTER PROCEDURE dbo.UpdateUserProfile
    @UserID INT,
    @Username NVARCHAR(20),
    @Email NVARCHAR(254)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.Users
    SET Username = @Username,
        Email = @Email
    WHERE UserID = @UserID
      AND IsRemoved = 0;

    IF @@ROWCOUNT = 0
        THROW 50004, 'User was not found or has been removed.', 1;
END;
GO

CREATE OR ALTER PROCEDURE dbo.SearchStoreGames
    @SearchTerm NVARCHAR(100) = NULL,
    @GenreID INT = NULL,
    @MinPrice DECIMAL(10,2) = NULL,
    @MaxPrice DECIMAL(10,2) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        G.GameID,
        G.Title,
        G.Price,
        G.ReleaseDate
    FROM dbo.StoreGames AS G
    WHERE G.IsRemoved = 0
      AND (@SearchTerm IS NULL OR G.Title LIKE N'%' + @SearchTerm + N'%')
      AND (@MinPrice IS NULL OR G.Price >= @MinPrice)
      AND (@MaxPrice IS NULL OR G.Price <= @MaxPrice)
      AND (
          @GenreID IS NULL
          OR EXISTS (
              SELECT 1
              FROM dbo.GameGenres AS GG
              WHERE GG.GameID = G.GameID
                AND GG.GenreID = @GenreID
          )
      )
    ORDER BY G.Title, G.GameID;
END;
GO

CREATE OR ALTER PROCEDURE dbo.GetUserLibrary
    @UserID INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        L.LibraryItemID,
        G.GameID,
        G.Title,
        L.DateAdded,
        L.PlaytimeMinutes
    FROM dbo.LibraryItems AS L
    INNER JOIN dbo.StoreGames AS G ON G.GameID = L.GameID
    WHERE L.UserID = @UserID
    ORDER BY G.Title;
END;
GO

CREATE OR ALTER PROCEDURE dbo.GetGameReviews
    @GameID INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        R.ReviewID,
        U.Username,
        R.Rating,
        R.ReviewText,
        R.ReviewDate
    FROM dbo.Reviews AS R
    INNER JOIN dbo.LibraryItems AS L ON L.LibraryItemID = R.LibraryItemID
    INNER JOIN dbo.Users AS U ON U.UserID = L.UserID
    WHERE L.GameID = @GameID
      AND U.IsRemoved = 0
    ORDER BY R.ReviewDate DESC, R.ReviewID DESC;
END;
GO

/* Return a user's purchase history with one row per purchased game. */
CREATE OR ALTER PROCEDURE dbo.GetPurchaseHistory
    @UserID INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        P.PurchaseID,
        P.PurchaseTime,
        G.GameID,
        G.Title,
        PI.PriceAtPurchase
    FROM dbo.Purchases AS P
    INNER JOIN dbo.PurchaseItems AS PI ON PI.PurchaseID = P.PurchaseID
    INNER JOIN dbo.StoreGames AS G ON G.GameID = PI.GameID
    WHERE P.UserID = @UserID
    ORDER BY P.PurchaseTime DESC, P.PurchaseID DESC, G.Title;
END;
GO

CREATE OR ALTER PROCEDURE dbo.GetWalletBalance
    @UserID INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        @UserID AS UserID,
        COALESCE(SUM(T.Amount * TT.BalanceEffect), 0.00) AS WalletBalance
    FROM dbo.UsersTransactions AS T
    INNER JOIN dbo.TransactionTypes AS TT
        ON TT.TransactionTypeID = T.TransactionTypeID
    WHERE T.UserID = @UserID;
END;
GO

CREATE OR ALTER PROCEDURE dbo.AddWalletDeposit
    @UserID INT,
    @Amount DECIMAL(10,2)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @DepositTypeID TINYINT;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @Amount <= 0
            THROW 50010, 'Deposit amount must be greater than zero.', 1;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Users WITH (UPDLOCK, HOLDLOCK)
            WHERE UserID = @UserID AND IsRemoved = 0
        )
            THROW 50011, 'User was not found or has been removed.', 1;

        SELECT @DepositTypeID = TransactionTypeID
        FROM dbo.TransactionTypes
        WHERE TypeName = N'Deposit';

        IF @DepositTypeID IS NULL
            THROW 50012, 'Deposit transaction type is not configured.', 1;

        INSERT INTO dbo.UsersTransactions
            (UserID, PurchaseID, TransactionTypeID, Amount)
        VALUES
            (@UserID, NULL, @DepositTypeID, @Amount);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO


CREATE OR ALTER PROCEDURE dbo.Checkout
    @UserID INT,
    @Cart dbo.GameCart READONLY,
    @PurchaseID INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Total DECIMAL(19,2);
    DECLARE @Balance DECIMAL(19,2);
    DECLARE @PurchaseTypeID TINYINT;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Users WITH (UPDLOCK, HOLDLOCK)
            WHERE UserID = @UserID AND IsRemoved = 0
        )
            THROW 50020, 'User was not found or has been removed.', 1;

        IF NOT EXISTS (SELECT 1 FROM @Cart)
            THROW 50021, 'The shopping cart is empty.', 1;

        IF EXISTS (
            SELECT 1
            FROM @Cart AS C
            LEFT JOIN dbo.StoreGames AS G WITH (UPDLOCK, HOLDLOCK)
                ON G.GameID = C.GameID
            WHERE G.GameID IS NULL OR G.IsRemoved = 1
        )
            THROW 50022, 'A game in the cart does not exist or is unavailable.', 1;

        IF EXISTS (
            SELECT 1
            FROM @Cart AS C
            INNER JOIN dbo.LibraryItems AS L ON L.GameID = C.GameID
            WHERE L.UserID = @UserID
        )
            THROW 50023, 'The user already owns a game in this cart.', 1;

        SELECT @Total = SUM(G.Price)
        FROM @Cart AS C
        INNER JOIN dbo.StoreGames AS G ON G.GameID = C.GameID;

        SELECT @Balance = COALESCE(SUM(T.Amount * TT.BalanceEffect), 0.00)
        FROM dbo.UsersTransactions AS T
        INNER JOIN dbo.TransactionTypes AS TT
            ON TT.TransactionTypeID = T.TransactionTypeID
        WHERE T.UserID = @UserID;

        IF @Balance < @Total
            THROW 50024, 'The wallet has insufficient funds.', 1;

        SELECT @PurchaseTypeID = TransactionTypeID
        FROM dbo.TransactionTypes
        WHERE TypeName = N'Purchase';

        IF @PurchaseTypeID IS NULL
            THROW 50025, 'Purchase transaction type is not configured.', 1;

        INSERT INTO dbo.Purchases (UserID)
        VALUES (@UserID);

        SET @PurchaseID = CONVERT(INT, SCOPE_IDENTITY());

        INSERT INTO dbo.PurchaseItems (PurchaseID, GameID, PriceAtPurchase)
        SELECT @PurchaseID, G.GameID, G.Price
        FROM @Cart AS C
        INNER JOIN dbo.StoreGames AS G ON G.GameID = C.GameID;

        INSERT INTO dbo.LibraryItems (UserID, GameID)
        SELECT @UserID, C.GameID
        FROM @Cart AS C;

        IF @Total > 0
        BEGIN
            INSERT INTO dbo.UsersTransactions
                (UserID, PurchaseID, TransactionTypeID, Amount)
            VALUES
                (@UserID, @PurchaseID, @PurchaseTypeID, @Total);
        END;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

/* Add minutes to a user's existing library entry. */
CREATE OR ALTER PROCEDURE dbo.AddPlaytime
    @UserID INT,
    @GameID INT,
    @AdditionalMinutes INT
AS
BEGIN
    SET NOCOUNT ON;

    IF @AdditionalMinutes <= 0
        THROW 50030, 'Additional playtime must be greater than zero.', 1;

    UPDATE dbo.LibraryItems
    SET PlaytimeMinutes = PlaytimeMinutes + @AdditionalMinutes
    WHERE UserID = @UserID AND GameID = @GameID;

    IF @@ROWCOUNT = 0
        THROW 50031, 'The game was not found in this user library.', 1;
END;
GO

CREATE OR ALTER PROCEDURE dbo.CreateReview
    @UserID INT,
    @GameID INT,
    @Rating TINYINT,
    @ReviewText NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Rating NOT BETWEEN 1 AND 5
        THROW 50040, 'Rating must be between 1 and 5.', 1;

    INSERT INTO dbo.Reviews (LibraryItemID, Rating, ReviewText)
    SELECT L.LibraryItemID, @Rating, @ReviewText
    FROM dbo.LibraryItems AS L
    WHERE L.UserID = @UserID AND L.GameID = @GameID;

    IF @@ROWCOUNT = 0
        THROW 50041, 'The user must own the game before reviewing it.', 1;
END;
GO

CREATE OR ALTER PROCEDURE dbo.UpdateReview
    @UserID INT,
    @ReviewID INT,
    @Rating TINYINT,
    @ReviewText NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Rating NOT BETWEEN 1 AND 5
        THROW 50042, 'Rating must be between 1 and 5.', 1;

    UPDATE R
    SET Rating = @Rating,
        ReviewText = @ReviewText,
        ReviewDate = SYSDATETIMEOFFSET()
    FROM dbo.Reviews AS R
    INNER JOIN dbo.LibraryItems AS L
        ON L.LibraryItemID = R.LibraryItemID
    WHERE R.ReviewID = @ReviewID
      AND L.UserID = @UserID;

    IF @@ROWCOUNT = 0
        THROW 50043, 'Review was not found for this user.', 1;
END;
GO

CREATE OR ALTER PROCEDURE dbo.AddStoreGame
    @Title NVARCHAR(200),
    @Price DECIMAL(10,2),
    @ReleaseDate DATE = NULL,
    @SourceGameID NVARCHAR(100) = NULL,
    @NewGameID INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    IF @Price < 0
        THROW 50050, 'Game price cannot be negative.', 1;

    INSERT INTO dbo.StoreGames (SourceGameID, Title, Price, ReleaseDate)
    VALUES (@SourceGameID, @Title, @Price, @ReleaseDate);

    SET @NewGameID = CONVERT(INT, SCOPE_IDENTITY());
END;
GO

CREATE OR ALTER PROCEDURE dbo.UpdateStoreGame
    @GameID INT,
    @Title NVARCHAR(200),
    @Price DECIMAL(10,2),
    @ReleaseDate DATE = NULL,
    @IsRemoved BIT
AS
BEGIN
    SET NOCOUNT ON;

    IF @Price < 0
        THROW 50051, 'Game price cannot be negative.', 1;

    UPDATE dbo.StoreGames
    SET Title = @Title,
        Price = @Price,
        ReleaseDate = @ReleaseDate,
        IsRemoved = @IsRemoved
    WHERE GameID = @GameID;

    IF @@ROWCOUNT = 0
        THROW 50052, 'Game was not found.', 1;
END;
GO

CREATE OR ALTER PROCEDURE dbo.AssignGameGenre
    @GameID INT,
    @GenreID INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.GameGenres WHERE GameID = @GameID AND GenreID = @GenreID)
        INSERT INTO dbo.GameGenres (GameID, GenreID) VALUES (@GameID, @GenreID);
END;
GO

CREATE OR ALTER PROCEDURE dbo.RemoveGameGenre
    @GameID INT,
    @GenreID INT
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM dbo.GameGenres
    WHERE GameID = @GameID AND GenreID = @GenreID;
END;
GO

CREATE OR ALTER PROCEDURE dbo.RecordRefund
    @UserID INT,
    @PurchaseID INT,
    @Amount DECIMAL(10,2)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @RefundTypeID TINYINT;
    DECLARE @PurchaseTotal DECIMAL(19,2);
    DECLARE @AlreadyRefunded DECIMAL(19,2);

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @Amount <= 0
            THROW 50060, 'Refund amount must be greater than zero.', 1;

        IF NOT EXISTS (
            SELECT 1 FROM dbo.Users WITH (UPDLOCK, HOLDLOCK)
            WHERE UserID = @UserID AND IsRemoved = 0
        )
            THROW 50061, 'User was not found or has been removed.', 1;

        SELECT @PurchaseTotal = SUM(PriceAtPurchase)
        FROM dbo.PurchaseItems
        WHERE PurchaseID = @PurchaseID;

        IF @PurchaseTotal IS NULL OR NOT EXISTS (
            SELECT 1 FROM dbo.Purchases
            WHERE PurchaseID = @PurchaseID AND UserID = @UserID
        )
            THROW 50062, 'Purchase was not found for this user.', 1;

        SELECT @AlreadyRefunded = COALESCE(SUM(Amount), 0.00)
        FROM dbo.UsersTransactions
        WHERE UserID = @UserID
          AND PurchaseID = @PurchaseID
          AND TransactionTypeID = 3;

        IF @AlreadyRefunded + @Amount > @PurchaseTotal
            THROW 50063, 'Refund exceeds the unrefunded purchase amount.', 1;

        SELECT @RefundTypeID = TransactionTypeID
        FROM dbo.TransactionTypes
        WHERE TypeName = N'Refund';

        IF @RefundTypeID IS NULL
            THROW 50064, 'Refund transaction type is not configured.', 1;

        INSERT INTO dbo.UsersTransactions
            (UserID, PurchaseID, TransactionTypeID, Amount)
        VALUES
            (@UserID, @PurchaseID, @RefundTypeID, @Amount);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

/* agg query 1 1: monthly best-selling games ranked by revenue. */
CREATE OR ALTER PROCEDURE dbo.GetMonthlyBestSellingGames
    @FirstDate DATE,
    @LastDate DATE
AS
BEGIN
    SET NOCOUNT ON;

    IF @LastDate < @FirstDate
        THROW 50070, 'LastDate must be on or after FirstDate.', 1;

    ;WITH GameMonthSales AS (
        SELECT
            YEAR(P.PurchaseTime) AS PurchaseYear,
            MONTH(P.PurchaseTime) AS PurchaseMonth,
            G.GameID,
            G.Title,
            COUNT_BIG(*) AS UnitsSold,
            SUM(PI.PriceAtPurchase) AS Revenue
        FROM dbo.Purchases AS P
        INNER JOIN dbo.PurchaseItems AS PI ON PI.PurchaseID = P.PurchaseID
        INNER JOIN dbo.StoreGames AS G ON G.GameID = PI.GameID
        WHERE CAST(P.PurchaseTime AS DATE) BETWEEN @FirstDate AND @LastDate
        GROUP BY YEAR(P.PurchaseTime), MONTH(P.PurchaseTime), G.GameID, G.Title
    )
    SELECT
        PurchaseYear,
        PurchaseMonth,
        GameID,
        Title,
        UnitsSold,
        Revenue,
        RANK() OVER (
            PARTITION BY PurchaseYear, PurchaseMonth
            ORDER BY Revenue DESC
        ) AS MonthlyRank
    FROM GameMonthSales
    ORDER BY PurchaseYear, PurchaseMonth, Revenue DESC, GameID;
END;
GO

/* agg query 2: fame counts, copies owned, reviews, rating, and playtime by genre. */
CREATE OR ALTER PROCEDURE dbo.GetGenrePerformance
    @MinReviewCount INT
AS
BEGIN
    SET NOCOUNT ON;

    IF @MinReviewCount < 0
        THROW 50071, 'MinReviewCount cannot be negative.', 1;

    ;WITH GenreGameCounts AS (
        SELECT GG.GenreID, COUNT_BIG(*) AS GameCount
        FROM dbo.GameGenres AS GG
        GROUP BY GG.GenreID
    ),
    GenreOwnership AS (
        SELECT
            GG.GenreID,
            COUNT_BIG(L.LibraryItemID) AS CopiesOwned,
            AVG(CAST(L.PlaytimeMinutes AS DECIMAL(18,2))) AS AveragePlaytimeMinutes
        FROM dbo.GameGenres AS GG
        LEFT JOIN dbo.LibraryItems AS L ON L.GameID = GG.GameID
        GROUP BY GG.GenreID
    ),
    GenreReviewStats AS (
        SELECT
            GG.GenreID,
            COUNT_BIG(R.ReviewID) AS ReviewCount,
            AVG(CAST(R.Rating AS DECIMAL(5,2))) AS AverageRating
        FROM dbo.GameGenres AS GG
        INNER JOIN dbo.LibraryItems AS L ON L.GameID = GG.GameID
        INNER JOIN dbo.Reviews AS R ON R.LibraryItemID = L.LibraryItemID
        GROUP BY GG.GenreID
    )
    SELECT
        G.GenreID,
        G.GenreName,
        GGC.GameCount,
        COALESCE(GO.CopiesOwned, 0) AS CopiesOwned,
        COALESCE(GRS.ReviewCount, 0) AS ReviewCount,
        GRS.AverageRating,
        GO.AveragePlaytimeMinutes
    FROM dbo.Genre AS G
    INNER JOIN GenreGameCounts AS GGC ON GGC.GenreID = G.GenreID
    LEFT JOIN GenreOwnership AS GO ON GO.GenreID = G.GenreID
    LEFT JOIN GenreReviewStats AS GRS ON GRS.GenreID = G.GenreID
    WHERE COALESCE(GRS.ReviewCount, 0) >= @MinReviewCount
    ORDER BY G.GenreName;
END;
GO

/* agg query 3: highest-spending customers in a date range. */
CREATE OR ALTER PROCEDURE dbo.GetTopCustomersBySpending
    @FirstDate DATE,
    @LastDate DATE,
    @TopN INT
AS
BEGIN
    SET NOCOUNT ON;

    IF @LastDate < @FirstDate
        THROW 50072, 'LastDate must be on or after FirstDate.', 1;
    IF @TopN < 1
        THROW 50073, 'TopN must be at least 1.', 1;

    ;WITH OrderTotals AS (
        SELECT
            P.PurchaseID,
            P.UserID,
            SUM(PI.PriceAtPurchase) AS OrderTotal,
            COUNT_BIG(*) AS GamesInOrder
        FROM dbo.Purchases AS P
        INNER JOIN dbo.PurchaseItems AS PI ON PI.PurchaseID = P.PurchaseID
        WHERE CAST(P.PurchaseTime AS DATE) BETWEEN @FirstDate AND @LastDate
        GROUP BY P.PurchaseID, P.UserID
    ),
    CustomerTotals AS (
        SELECT
            OT.UserID,
            COUNT_BIG(*) AS PurchaseCount,
            SUM(OT.OrderTotal) AS TotalSpent,
            AVG(OT.OrderTotal) AS AverageOrderValue,
            SUM(OT.GamesInOrder) AS GamesAcquired
        FROM OrderTotals AS OT
        GROUP BY OT.UserID
    )
    SELECT TOP (@TopN)
        CT.UserID,
        U.Username,
        CT.PurchaseCount,
        CT.TotalSpent,
        CT.AverageOrderValue,
        CT.GamesAcquired,
        DENSE_RANK() OVER (ORDER BY CT.TotalSpent DESC) AS SpendRank
    FROM CustomerTotals AS CT
    INNER JOIN dbo.Users AS U ON U.UserID = CT.UserID
    ORDER BY CT.TotalSpent DESC, CT.UserID;
END;
GO

/* agg query 4: wallet transactions by month/type and running net balance. */
CREATE OR ALTER PROCEDURE dbo.GetWalletActivityByMonth
    @FirstDate DATE,
    @LastDate DATE
AS
BEGIN
    SET NOCOUNT ON;

    IF @LastDate < @FirstDate
        THROW 50074, 'LastDate must be on or after FirstDate.', 1;

    ;WITH MonthlyTypeTotals AS (
        SELECT
            YEAR(T.TransactionDate) AS TransactionYear,
            MONTH(T.TransactionDate) AS TransactionMonth,
            TT.TransactionTypeID,
            TT.TypeName AS TransactionType,
            COUNT_BIG(*) AS TransactionCount,
            SUM(T.Amount) AS TotalAmount,
            SUM(T.Amount * TT.BalanceEffect) AS NetAmount
        FROM dbo.UsersTransactions AS T
        INNER JOIN dbo.TransactionTypes AS TT
            ON TT.TransactionTypeID = T.TransactionTypeID
        WHERE CAST(T.TransactionDate AS DATE) BETWEEN @FirstDate AND @LastDate
        GROUP BY
            YEAR(T.TransactionDate), MONTH(T.TransactionDate),
            TT.TransactionTypeID, TT.TypeName
    ),
    MonthlyNet AS (
        SELECT
            TransactionYear,
            TransactionMonth,
            SUM(NetAmount) AS MonthNetAmount
        FROM MonthlyTypeTotals
        GROUP BY TransactionYear, TransactionMonth
    ),
    RunningMonthlyNet AS (
        SELECT
            TransactionYear,
            TransactionMonth,
            SUM(MonthNetAmount) OVER (
                ORDER BY TransactionYear, TransactionMonth
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ) AS RunningNetAmount
        FROM MonthlyNet
    )
    SELECT
        MTT.TransactionYear,
        MTT.TransactionMonth,
        MTT.TransactionType,
        MTT.TransactionCount,
        MTT.TotalAmount,
        RMN.RunningNetAmount
    FROM MonthlyTypeTotals AS MTT
    INNER JOIN RunningMonthlyNet AS RMN
        ON RMN.TransactionYear = MTT.TransactionYear
       AND RMN.TransactionMonth = MTT.TransactionMonth
    ORDER BY MTT.TransactionYear, MTT.TransactionMonth, MTT.TransactionType;
END;
GO
