USE master;

IF EXISTS (SELECT * FROM sys.databases WHERE name = 'Chapter7_AccountingService')
BEGIN
	PRINT 'Dropping database ''Chapter7_AccountingService''';
	DROP DATABASE Chapter7_AccountingService;
END
GO

CREATE DATABASE Chapter7_AccountingService
GO

USE Chapter7_AccountingService
GO

--****************************************************************************
-- * Create all objects necessary for the communication between the
-- * OrderService and the AccountingService. The AccountingService
-- * creates an accounting transaction that is stored in a accounting table.
--****************************************************************************

--***************************************************************************************
--*  Create the needed message types between the OrderService and the AccountingService
--***************************************************************************************
CREATE MESSAGE TYPE [http://ssb.csharp.at/SSB_Book/c07/AccountingRequestMessage] VALIDATION = WELL_FORMED_XML
CREATE MESSAGE TYPE [http://ssb.csharp.at/SSB_Book/c07/AccountingResponseMessage] VALIDATION = WELL_FORMED_XML
GO

--***************************************************************************
--*  Create the contract between the OrderService and the AccountingService
--***************************************************************************
CREATE CONTRACT [http://ssb.csharp.at/SSB_Book/c07/AccountingContract]
(
	[http://ssb.csharp.at/SSB_Book/c07/AccountingRequestMessage] SENT BY INITIATOR,
	[http://ssb.csharp.at/SSB_Book/c07/AccountingResponseMessage] SENT BY TARGET
)
GO

--*************************************************
--*  Create the queue "AccountingQueue"
--*************************************************
CREATE QUEUE AccountingQueue WITH STATUS = ON
GO

--************************************************************
--*  Create the service "CreditCardValidationService"
--************************************************************
CREATE SERVICE AccountingService
ON QUEUE AccountingQueue 
(
	[http://ssb.csharp.at/SSB_Book/c07/AccountingContract]
)
GO

--********************************************************************************************
--*  Create a table that stores the accounting recordings submitted to the AccountingService
--********************************************************************************************
CREATE TABLE AccountingRecordings
(
	AccountingRecordingsID UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
	CustomerID NVARCHAR(10) NOT NULL,
	Amount DECIMAL(18, 2) NOT NULL
)
GO

--*********************************************************************************************************
--*  Create the stored procedure that processes the AccountingRequest messages from the AccountingService
--*********************************************************************************************************
CREATE PROCEDURE ProcessAccountingRequestMessages
AS
	DECLARE @ch UNIQUEIDENTIFIER;
	DECLARE @messagetypename NVARCHAR(256);
	DECLARE	@messagebody XML;
	DECLARE @responsemessage XML;

	WHILE (1=1)
	BEGIN
		BEGIN TRANSACTION

		WAITFOR (
			RECEIVE TOP(1)
				@ch = conversation_handle,
				@messagetypename = message_type_name,
				@messagebody = CAST(message_body AS XML)
			FROM
				AccountingQueue
		), TIMEOUT 1000

		IF (@@ROWCOUNT = 0)
		BEGIN
			ROLLBACK TRANSACTION
			BREAK
		END

		IF (@messagetypename = 'http://ssb.csharp.at/SSB_Book/c07/AccountingRequestMessage')
		BEGIN
			-- Create a new booking record
			INSERT INTO AccountingRecordings (AccountingRecordingsID, CustomerID, Amount) 
			VALUES 
			(
				NEWID(), 
				@messagebody.value('/AccountingRequest[1]/CustomerID[1]', 'NVARCHAR(10)'),
				@messagebody.value('/AccountingRequest[1]/Amount[1]', 'DECIMAL(18, 2)')
			)

			-- Construct the response message
			SET @responsemessage = '<AccountingResponse>1</AccountingResponse>';

			-- Send the response message back to the OrderService
			SEND ON CONVERSATION @ch MESSAGE TYPE [http://ssb.csharp.at/SSB_Book/c07/AccountingResponseMessage] (@responsemessage);

			-- End the conversation on the target's side
			END CONVERSATION @ch;
		END

		IF (@messagetypename = 'http://schemas.microsoft.com/SQL/ServiceBroker/EndDialog')
		BEGIN
			-- End the conversation
			END CONVERSATION @ch;
		END

		COMMIT TRANSACTION
	END
GO

--**************************************************************
--*  Activate internal activation on the queue AccountingQueue
--**************************************************************
ALTER QUEUE AccountingQueue
WITH ACTIVATION
(
	STATUS = ON,
	PROCEDURE_NAME = ProcessAccountingRequestMessages,
	MAX_QUEUE_READERS = 1,
	EXECUTE AS SELF
)
GO

--********************************************************
--*  Create the necessary route back to the OrderService
--********************************************************
CREATE ROUTE OrderServiceRoute
	WITH SERVICE_NAME = 'OrderService',
	ADDRESS = 'TCP://OrderServiceInstance:4740'
GO

--*************************************
--*  Create a new database master key
--*************************************
USE master
GO

CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'password1!'
GO

--**********************************************************************
--*  Create the certificate that holds both the public and private key
--**********************************************************************
CREATE CERTIFICATE AccountingServiceCertPrivate
	WITH SUBJECT = 'For Service Broker authentication',
	START_DATE = '01/01/2006'
GO

--********************************************************************
--*  Create the Service Broker endpoint for this SQL Server instance
--********************************************************************
CREATE ENDPOINT AccountingServiceEndpoint
STATE = STARTED
AS TCP 
(
	LISTENER_PORT = 4742
)
FOR SERVICE_BROKER 
(
	AUTHENTICATION = CERTIFICATE AccountingServiceCertPrivate
)
GO

--*********************************************************
--*  Backup the public key of the new created certificate
--*********************************************************
BACKUP CERTIFICATE AccountingServiceCertPrivate
	TO FILE = 'c:\AccountingServiceCertPublic.cert'
GO

--*****************************************
--*  Add the login from the Order service 
--*****************************************
CREATE LOGIN OrderServiceLogin WITH PASSWORD = 'password1!'
GO

CREATE USER	OrderServiceUser FOR LOGIN OrderServiceLogin
GO

--*************************************************************
--*  Import the public key certificate from the Order service
--*************************************************************
CREATE CERTIFICATE OrderServiceCertPublic
	AUTHORIZATION OrderServiceUser
	FROM FILE = 'c:\OrderServiceCertPublic.cert'
GO

--***********************************************************
--*  Grant the CONNECT permission to the Accounting service
--***********************************************************
GRANT CONNECT ON ENDPOINT::AccountingServiceEndpoint TO OrderServiceLogin
GO

--********************************************************************
--*  Grant the SEND permission to the other SQL Server instance
--********************************************************************
USE Chapter7_AccountingService
GO

GRANT SEND ON SERVICE::[AccountingService] TO PUBLIC
GO





select * from accountingqueue

select * from sys.transmission_queue

exec processaccountingrequestmessages

select * from accountingrecordings
