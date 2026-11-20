
IF NOT EXISTS (SELECT 1 FROM dbo.TransactionTypes WHERE TransactionTypeID = 1)
    INSERT dbo.TransactionTypes (TransactionTypeID, TypeName, BalanceEffect)
    VALUES (1, N'Deposit', 1);

IF NOT EXISTS (SELECT 1 FROM dbo.TransactionTypes WHERE TransactionTypeID = 2)
    INSERT dbo.TransactionTypes (TransactionTypeID, TypeName, BalanceEffect)
    VALUES (2, N'Purchase', -1);

IF NOT EXISTS (SELECT 1 FROM dbo.TransactionTypes WHERE TransactionTypeID = 3)
    INSERT dbo.TransactionTypes (TransactionTypeID, TypeName, BalanceEffect)
    VALUES (3, N'Refund', 1);
GO


INSERT INTO dbo.Genre (GenreName)
SELECT V.GenreName
FROM (VALUES
    (N'Action'),
    (N'Adventure'),
    (N'Casual'),
    (N'Indie'),
    (N'RPG'),
    (N'Simulation'),
    (N'Sports'),
    (N'Strategy')
) AS V(GenreName)
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.Genre AS G WHERE G.GenreName = V.GenreName
);
GO


