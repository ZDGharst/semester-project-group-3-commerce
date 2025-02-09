USE CommerceBank_TransactionDB;
GO

DROP TRIGGER IF EXISTS GenerateNotifications;
GO

CREATE TRIGGER GenerateNotifications ON Financial_Transaction
AFTER INSERT
AS
BEGIN
	DECLARE @inserted_id INT;
	DECLARE @inserted_account_id INT;
	DECLARE @inserted_type VARCHAR(2);
	DECLARE @inserted_amount MONEY;
	DECLARE @inserted_balance_after MONEY;

	-- Operate on each row in the inserted table using a cursor.
	DECLARE inserted_cursor CURSOR FOR
	SELECT id, account_id, type, amount, balance_after
	FROM INSERTED

	OPEN inserted_cursor
	FETCH NEXT FROM inserted_cursor INTO @inserted_id, @inserted_account_id, @inserted_type, @inserted_amount, @inserted_balance_after
	WHILE @@FETCH_STATUS = 0
	BEGIN
		-- Find all the notification rules that belongs to all customers that own
		-- the account that the transaction was created on and store it in a
		-- temporary table.
		SELECT id, type, condition, value, notify_web, message
		INTO #Rules
		FROM Notification_Rule
		WHERE customer_id IN (
			SELECT customer_id FROM Customer_Account
			WHERE Customer_Account.account_id = @inserted_account_id
		);
		
		DECLARE @id INT;
		DECLARE @type VARCHAR(32);
		DECLARE @condition VARCHAR(32);
		DECLARE @value DECIMAL(18);
		DECLARE @read_by_user BIT;
		DECLARE @message VARCHAR(300);

		-- Iterate across the notification rules that the customer has.
		WHILE EXISTS(SELECT * FROM #Rules)
		BEGIN
			SELECT Top 1
				@id = id, @type = type, @condition = condition, @value = value, @read_by_user = notify_web, @message = message
			FROM #Rules;
			
			-- Check the notification type to see what conditions should be.
			IF @type = "Balance"
			BEGIN
				IF @condition = "Below" AND @value >= @inserted_balance_after
				BEGIN
					INSERT INTO Notification (transaction_id, notification_rule, read_by_user, message)
					VALUES (
						@inserted_id,
						@id,
						~@read_by_user,
						IIF(@message = 'NA' OR @message IS NULL, "The balance in one of your accounts is $" + LTRIM(STR(@inserted_balance_after)) +
						", which is below your low balance threshold of $" + LTRIM(STR(@value)) + ".", @message)
					);
				END
				IF @condition = "Above" AND @value <= @inserted_balance_after
				BEGIN
					INSERT INTO Notification (transaction_id, notification_rule, read_by_user, message)
					VALUES (
						@inserted_id,
						@id,
						~@read_by_user,
						IIF(@message = 'NA' OR @message IS NULL, "The balance in one of your accounts is $" + LTRIM(STR(@inserted_balance_after)) +
						", which is above your high balance threshold of $" + LTRIM(STR(@value)) + ".", @message)
					);
				END
			END
					
			IF @type = "Withdrawal" AND @inserted_type = "DR"
			BEGIN
				IF @condition = "Below" AND @value >= @inserted_amount
				BEGIN
					INSERT INTO Notification (transaction_id, notification_rule, read_by_user, message)
					VALUES (
						@inserted_id,
						@id,
						~@read_by_user,
						IIF(@message = 'NA' OR @message IS NULL, "A debit was posted in one of your accounts worth $" + LTRIM(STR(@inserted_amount)) +
						", which is below your withdrawal notification threshold of $" + LTRIM(STR(@value)) + ".", @message)
					);
				END
				IF @condition = "Above" AND @value <= @inserted_amount
				BEGIN
					INSERT INTO Notification (transaction_id, notification_rule, read_by_user, message)
					VALUES (
						@inserted_id,
						@id,
						~@read_by_user,
						IIF(@message = 'NA' OR @message IS NULL, "A debit was posted in one of your accounts worth $" + LTRIM(STR(@inserted_amount)) +
						", which is above your withdrawal notification threshold of $" + LTRIM(STR(@value)) + ".", @message)
					);
				END
			END
					
			IF @type = "Deposit" AND @inserted_type = "CR"
			BEGIN
				IF @condition = "Below" AND @value >= @inserted_amount
				BEGIN
					INSERT INTO Notification (transaction_id, notification_rule, read_by_user, message)
					VALUES (
						@inserted_id,
						@id,
						~@read_by_user,
						IIF(@message = 'NA' OR @message IS NULL, "A credit was posted in one of your accounts worth $" + LTRIM(STR(@inserted_amount)) +
						", which is below your deposit notification threshold of $" + LTRIM(STR(@value)) + ".", @message)
					);
				END
				IF @condition = "Above" AND @value <= @inserted_amount
				BEGIN
					INSERT INTO Notification (transaction_id, notification_rule, read_by_user, message)
					VALUES (
						@inserted_id,
						@id,
						~@read_by_user,
						IIF(@message = 'NA' OR @message IS NULL, "A credit was posted in one of your accounts worth $" + LTRIM(STR(@inserted_amount)) +
						", which is above your deposit notification threshold of $" + LTRIM(STR(@value)) + ".", @message)
					);
				END
			END
			
			-- Delete the row from the temporary table.
			DELETE #Rules WHERE id = @id;
		END
		FETCH NEXT FROM inserted_cursor INTO @inserted_id, @inserted_account_id, @inserted_type, @inserted_amount, @inserted_balance_after
	END
	CLOSE inserted_cursor
	DEALLOCATE inserted_cursor
END

GO
