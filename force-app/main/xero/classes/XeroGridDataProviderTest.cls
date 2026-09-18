@IsTest
private class XeroGridDataProviderTest {

    private static void setupConfig() {
    }

    private static String sampleInvoicesJson() {
        return '{"Invoices":[' +
            '{"InvoiceID":"inv-001","InvoiceNumber":"INV-001","Contact":{"Name":"Ridgeway University"},' +
            '"Date":"2026-08-20","DueDate":"2026-09-20","Total":450.00,"AmountDue":450.00,"AmountPaid":0,' +
            '"Status":"AUTHORISED","CurrencyCode":"NZD","Reference":"Monthly retainer","Type":"ACCREC"},' +
            '{"InvoiceID":"inv-002","InvoiceNumber":"INV-002","Contact":{"Name":"Marine Systems"},' +
            '"Date":"2026-08-21","DueDate":"2026-08-15","Total":300.00,"AmountDue":0,"AmountPaid":300.00,' +
            '"Status":"PAID","CurrencyCode":"NZD","Type":"ACCREC"}' +
        ']}';
    }

    private static String sampleContactsJson() {
        return '{"Contacts":[' +
            '{"ContactID":"c-001","Name":"Ridgeway University","FirstName":"Richard","LastName":"Ridge",' +
            '"EmailAddress":"richard@ridgeway.edu","ContactStatus":"ACTIVE","IsSupplier":false,"IsCustomer":true,' +
            '"Phones":[{"PhoneType":"DEFAULT","PhoneNumber":"555-1234"},{"PhoneType":"FAX","PhoneNumber":"555-9999"}]}' +
        ']}';
    }

    private static String sampleAccountsJson() {
        return '{"Accounts":[' +
            '{"AccountID":"a-001","Code":"200","Name":"Sales","Type":"REVENUE","TaxType":"OUTPUT2",' +
            '"Status":"ACTIVE","Class":"REVENUE","Description":"Income from trading","EnablePaymentsToAccount":false}' +
        ']}';
    }

    private static String samplePaymentsJson() {
        return '{"Payments":[' +
            '{"PaymentID":"p-001","Date":"2026-08-25","Invoice":{"InvoiceNumber":"INV-002"},' +
            '"Account":{"Name":"Business Account","Code":"090"},"Amount":300.00,' +
            '"Reference":"Ref-100","Status":"AUTHORISED","PaymentType":"ACCRECPAYMENT","CurrencyRate":1.0}' +
        ']}';
    }

    private static String sampleBankTransactionsJson() {
        return '{"BankTransactions":[' +
            '{"BankTransactionID":"bt-001","Date":"2026-08-26","Contact":{"Name":"Office Supplies Co"},' +
            '"BankAccount":{"Name":"Business Cheque"},"Type":"SPEND","Reference":"STAPLES-AUG",' +
            '"Total":85.50,"Status":"AUTHORISED","IsReconciled":true}' +
        ']}';
    }

    @IsTest
    static void getCapabilities_and_getData_invoices_withSearch() {
        setupConfig();

        XeroTestSupport.RoutingMock mock = new XeroTestSupport.RoutingMock();
        mock.byEndpointContains.put('/api.xro/2.0/Invoices',
            XeroTestSupport.makeResponse(200, sampleInvoicesJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        XeroGridDataProvider provider = new XeroGridDataProvider();
        XeroGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"tenantId":"tenant-abc-123","resource":"invoices"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities caps = provider.getCapabilities(ctx);

        appcg.GridDataProviderTypesV1.QueryRequest req = new appcg.GridDataProviderTypesV1.QueryRequest();
        req.context = ctx;
        req.searchTerm = 'INV-001';
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(req);
        Test.stopTest();

        System.assert(caps.columns.size() >= 10, 'Expected at least 10 invoice columns');
        System.assertEquals(true, caps.supportsServerPagination);
        System.assertEquals(100, caps.maxPageSize);
        System.assertEquals(1, page.records.size(), 'Search should return 1 match');
        System.assertEquals('INV-001', page.records[0].get('invoiceNumber'));
        System.assertEquals('Ridgeway University', page.records[0].get('contactName'));
        System.assertEquals('AUTHORISED', page.records[0].get('status'));
    }

    @IsTest
    static void getData_contacts() {
        setupConfig();

        XeroTestSupport.RoutingMock mock = new XeroTestSupport.RoutingMock();
        mock.byEndpointContains.put('/api.xro/2.0/Contacts',
            XeroTestSupport.makeResponse(200, sampleContactsJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        XeroGridDataProvider provider = new XeroGridDataProvider();
        XeroGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"tenantId":"tenant-abc-123","resource":"contacts"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities caps = provider.getCapabilities(ctx);

        appcg.GridDataProviderTypesV1.QueryRequest req = new appcg.GridDataProviderTypesV1.QueryRequest();
        req.context = ctx;
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(req);
        Test.stopTest();

        System.assertEquals(1, page.records.size());
        System.assertEquals('Ridgeway University', page.records[0].get('name'));
        System.assertEquals('richard@ridgeway.edu', page.records[0].get('emailAddress'));
        System.assertEquals('555-1234', page.records[0].get('phone'));
        System.assertEquals(true, page.records[0].get('isCustomer'));
        System.assertEquals(false, page.records[0].get('isSupplier'));
    }

    @IsTest
    static void getData_accounts() {
        setupConfig();

        XeroTestSupport.RoutingMock mock = new XeroTestSupport.RoutingMock();
        mock.byEndpointContains.put('/api.xro/2.0/Accounts',
            XeroTestSupport.makeResponse(200, sampleAccountsJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        XeroGridDataProvider provider = new XeroGridDataProvider();
        XeroGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"tenantId":"tenant-abc-123","resource":"accounts"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities caps = provider.getCapabilities(ctx);

        appcg.GridDataProviderTypesV1.QueryRequest req = new appcg.GridDataProviderTypesV1.QueryRequest();
        req.context = ctx;
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(req);
        Test.stopTest();

        System.assertEquals(1, page.records.size());
        System.assertEquals('200', page.records[0].get('code'));
        System.assertEquals('Sales', page.records[0].get('name'));
        System.assertEquals('REVENUE', page.records[0].get('type'));
        System.assertEquals('ACTIVE', page.records[0].get('status'));
    }

    @IsTest
    static void getData_payments() {
        setupConfig();

        XeroTestSupport.RoutingMock mock = new XeroTestSupport.RoutingMock();
        mock.byEndpointContains.put('/api.xro/2.0/Payments',
            XeroTestSupport.makeResponse(200, samplePaymentsJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        XeroGridDataProvider provider = new XeroGridDataProvider();
        XeroGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"tenantId":"tenant-abc-123","resource":"payments"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities caps = provider.getCapabilities(ctx);

        appcg.GridDataProviderTypesV1.QueryRequest req = new appcg.GridDataProviderTypesV1.QueryRequest();
        req.context = ctx;
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(req);
        Test.stopTest();

        System.assertEquals(1, page.records.size());
        System.assertEquals('INV-002', page.records[0].get('invoiceNumber'));
        System.assertEquals('Business Account', page.records[0].get('accountName'));
        System.assertEquals(300.00, page.records[0].get('amount'));
    }

    @IsTest
    static void getData_bills() {
        setupConfig();

        // Bills use the Invoices endpoint with Type==ACCPAY filter
        XeroTestSupport.RoutingMock mock = new XeroTestSupport.RoutingMock();
        mock.byEndpointContains.put('/api.xro/2.0/Invoices',
            XeroTestSupport.makeResponse(200, sampleInvoicesJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        XeroGridDataProvider provider = new XeroGridDataProvider();
        XeroGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"tenantId":"tenant-abc-123","resource":"bills"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities caps = provider.getCapabilities(ctx);

        appcg.GridDataProviderTypesV1.QueryRequest req = new appcg.GridDataProviderTypesV1.QueryRequest();
        req.context = ctx;
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(req);
        Test.stopTest();

        System.assertEquals(2, page.records.size());
        System.assert(caps.columns.size() >= 8, 'Bills should have at least 8 columns');
    }

    @IsTest
    static void getData_bankTransactions() {
        setupConfig();

        XeroTestSupport.RoutingMock mock = new XeroTestSupport.RoutingMock();
        mock.byEndpointContains.put('/api.xro/2.0/BankTransactions',
            XeroTestSupport.makeResponse(200, sampleBankTransactionsJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        XeroGridDataProvider provider = new XeroGridDataProvider();
        XeroGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"tenantId":"tenant-abc-123","resource":"banktransactions"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities caps = provider.getCapabilities(ctx);

        appcg.GridDataProviderTypesV1.QueryRequest req = new appcg.GridDataProviderTypesV1.QueryRequest();
        req.context = ctx;
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(req);
        Test.stopTest();

        System.assertEquals(1, page.records.size());
        System.assertEquals('Office Supplies Co', page.records[0].get('contactName'));
        System.assertEquals('SPEND', page.records[0].get('type'));
        System.assertEquals(true, page.records[0].get('isReconciled'));
    }

    @IsTest
    static void parseConfig_validationErrors() {
        XeroGridDataProvider.testGridDef = null;
        try {
            XeroGridDataProvider.parseConfig(null);
            System.assert(false, 'Expected GridUiException');
        } catch (XeroGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('requires configuration'));
        }

        // Blank config
        XeroGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = ''
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();
        try {
            XeroGridDataProvider.parseConfig(ctx);
            System.assert(false, 'Expected GridUiException');
        } catch (XeroGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('requires configuration'));
        }

        // Missing tenantId
        XeroGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"resource":"invoices"}'
        );
        try {
            XeroGridDataProvider.parseConfig(ctx);
            System.assert(false, 'Expected GridUiException');
        } catch (XeroGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('tenantId'));
        }
    }

    @IsTest
    static void resolveEntityKey_coversAllResources() {
        System.assertEquals('Invoices', XeroGridDataProvider.resolveEntityKey('invoices'));
        System.assertEquals('Invoices', XeroGridDataProvider.resolveEntityKey('invoice'));
        System.assertEquals('Invoices', XeroGridDataProvider.resolveEntityKey('bills'));
        System.assertEquals('Contacts', XeroGridDataProvider.resolveEntityKey('contacts'));
        System.assertEquals('Accounts', XeroGridDataProvider.resolveEntityKey('accounts'));
        System.assertEquals('Payments', XeroGridDataProvider.resolveEntityKey('payments'));
        System.assertEquals('BankTransactions', XeroGridDataProvider.resolveEntityKey('banktransactions'));
        System.assertEquals('Invoices', XeroGridDataProvider.resolveEntityKey('unknown'));
    }

    @IsTest
    static void getData_emptyResponse() {
        setupConfig();

        XeroTestSupport.RoutingMock mock = new XeroTestSupport.RoutingMock();
        mock.byEndpointContains.put('/api.xro/2.0/Invoices',
            XeroTestSupport.makeResponse(200, '{"Invoices":[]}'));
        Test.setMock(HttpCalloutMock.class, mock);

        XeroGridDataProvider provider = new XeroGridDataProvider();
        XeroGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"tenantId":"tenant-abc-123","resource":"invoices"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        Test.startTest();
        provider.getCapabilities(ctx);

        appcg.GridDataProviderTypesV1.QueryRequest req = new appcg.GridDataProviderTypesV1.QueryRequest();
        req.context = ctx;
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(req);
        Test.stopTest();

        System.assertEquals(0, page.records.size());
        System.assertEquals(0, page.totalCount);
    }
}
