SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


/*
  dbo.sp_income
  JSON param supports multiple rows under "$.income".

  Actions:
    1 = INSERT
    2 = UPDATE
    3 = DELETE
*/

ALTER PROC [dbo].[sp_income]
  @pjsonfile NVARCHAR(MAX)
AS

BEGIN
  SET NOCOUNT ON;

  /*declare  @pjsonfile NVARCHAR(MAX) = '{
  "income": [
    {
      "action": 1,
      "total": 250.50,
      "paymentMethod": "Tarjeta",
      "paymentDate": "2025-10-23T22:30:00",
      "userId": 1,
      "clientId": 1,
      "companyId": 1,
      "productId": 1,
      "companyId": 1,
      "options":{
        "productOptionId": 1,
        "OptionChoice": {
            "productOptionChoiceId": 10,
            "name": "",
            "price": -50.00
        },
        {
            "id": 11,
            "name": "Petit",
            "price": -30.00
        }
      }
    }
  ]
}'*/

  DECLARE @Outputmessage NVARCHAR(MAX) = N'
  {
    "result": [
      { "value": "", "msg": "", "error": "" }
    ]
  }',
  @Error NVARCHAR(500) = N'';

  BEGIN TRY
    IF @pjsonfile IS NULL OR TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.income[0].action')) IS NULL
      RAISERROR('Invalid or missing JSON/action.', 16, 1);

    DECLARE @action INT =
      TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.income[0].action'));

    -- Optional: validate companies exist for INSERT/UPDATE payloads
    IF @action IN (1,2)
    BEGIN
      IF EXISTS (
        SELECT 1
        FROM OPENJSON(@pjsonfile, '$.income')
             WITH (companyId INT '$.companyId') j
        WHERE j.companyId IS NULL
      )
        RAISERROR('companyId is required for all rows.', 16, 1);

      IF EXISTS (
        SELECT 1
        FROM OPENJSON(@pjsonfile, '$.income')
             WITH (companyId INT '$.companyId') j
        WHERE NOT EXISTS (SELECT 1 FROM dbo.companies c WHERE c.companyId = j.companyId)
      )
        RAISERROR('One or more companyId values do not exist.', 16, 1);
    END

    BEGIN TRAN;

    IF @action = 1
    BEGIN
      -- INSERT: support multiple rows
      DECLARE @Inserted TABLE (incomeId INT);

      INSERT INTO dbo.income
      (
        orderId,
        total,
        paymentMethod,
        paymentDate,
        userId,
        clientId,
        companyId
      )
      OUTPUT inserted.incomeId INTO @Inserted(incomeId)
      SELECT
        j.orderId,
        j.total,
        j.paymentMethod,
        COALESCE(j.paymentDate, GETDATE()),
        j.userId,
        j.clientId,
        j.companyId
      FROM OPENJSON(@pjsonfile, '$.income')
      WITH
      (
        orderId        INT             '$.orderId',
        total          DECIMAL(10,2)   '$.total',
        paymentMethod  NVARCHAR(20)    '$.paymentMethod',
        paymentDate    DATETIME2       '$.paymentDate',
        userId         INT             '$.userId',
        clientId       INT             '$.clientId',
        companyId      INT             '$.companyId'
      ) AS j;

      -- Return CSV of inserted ids in "value"
      DECLARE @ids NVARCHAR(MAX) =
      (
        SELECT STRING_AGG(CAST(incomeId AS NVARCHAR(20)), ',')
        FROM @Inserted
      );

      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', ISNULL(@ids, N''));
      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', N'Inserted Successfully');
    END
    ELSE IF @action = 2
    BEGIN
      -- UPDATE: only update fields that are present (leave others unchanged)
      ;WITH J AS
      (
        SELECT *
        FROM OPENJSON(@pjsonfile, '$.income')
        WITH
        (
          incomeId       INT            '$.incomeId',
          orderId        INT            '$.orderId',
          total          DECIMAL(10,2)  '$.total',
          paymentMethod  NVARCHAR(20)   '$.paymentMethod',
          paymentDate    DATETIME2      '$.paymentDate',
          userId         INT            '$.userId',
          clientId       INT            '$.clientId',
          companyId      INT            '$.companyId'
        )
      )
      UPDATE i
         SET
           orderId       = COALESCE(j.orderId, i.orderId),
           total         = COALESCE(j.total, i.total),
           paymentMethod = COALESCE(j.paymentMethod, i.paymentMethod),
           paymentDate   = COALESCE(j.paymentDate, i.paymentDate),
           userId        = COALESCE(j.userId, i.userId),
           clientId      = COALESCE(j.clientId, i.clientId),
           companyId     = COALESCE(j.companyId, i.companyId)
      FROM dbo.income AS i
      INNER JOIN J AS j
              ON j.incomeId = i.incomeId;

      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', N'Updated Successfully');
    END
    ELSE IF @action = 3
    BEGIN
      -- DELETE: supports multiple ids
      DELETE i
      FROM dbo.income AS i
      INNER JOIN OPENJSON(@pjsonfile, '$.income')
              WITH (incomeId INT '$.incomeId') j
              ON j.incomeId = i.incomeId;

      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', N'Deleted Successfully');
    END
    ELSE
    BEGIN
      RAISERROR('Invalid action. Use 1=INSERT, 2=UPDATE, 3=DELETE.', 16, 1);
    END

    COMMIT TRAN;
  END TRY
  BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;

    SET @Error = ERROR_MESSAGE();
    SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
    SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', @Error);
  END CATCH;

  -- Return result as rows (same style as your example)
  SELECT
      JSON_VALUE(value, '$.value') AS [value],
      JSON_VALUE(value, '$.msg')   AS [msg],
      JSON_VALUE(value, '$.error') AS [error]
  FROM OPENJSON(@Outputmessage, '$.result');
END
GO
