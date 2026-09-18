@IsTest
private class XeroClientTest {

    private static XeroTestSupport.SingleResponseMock arrange(String responseBody) {

        XeroTestSupport.SingleResponseMock mock = new XeroTestSupport.SingleResponseMock();
        mock.statusCode = 200;
        mock.body = responseBody;
        Test.setMock(HttpCalloutMock.class, mock);
        return mock;
    }

    @IsTest
    static void listInvoices_dispatchesGet_withTenantHeader() {
        XeroTestSupport.SingleResponseMock mock = arrange(
            '{"Invoices":[{"InvoiceID":"INV-001","InvoiceNumber":"INV-001","Total":500.0}]}'
        );

        Test.startTest();
        Map<String, Object> result = new XeroClient().listInvoices('tenant-abc-123', null);
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/api.xro/2.0/Invoices'), mock.lastEndpoint);
        System.assert(result.containsKey('Invoices'));
        System.assertEquals('tenant-abc-123', mock.capturedHeaders.get('xero-tenant-id'));
    }

    @IsTest
    static void listInvoices_withPageAndWhereClause() {
        XeroTestSupport.SingleResponseMock mock = arrange(
            '{"Invoices":[]}'
        );

        Test.startTest();
        Map<String, Object> result = new XeroClient().listInvoices('tenant-abc-123', 2, 'Type=="ACCREC"');
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('page=2'), mock.lastEndpoint);
        System.assert(mock.lastEndpoint.contains('where='), mock.lastEndpoint);
    }

    @IsTest
    static void listContacts_dispatchesGet() {
        XeroTestSupport.SingleResponseMock mock = arrange(
            '{"Contacts":[{"ContactID":"C1","Name":"Acme Corp"}]}'
        );

        Test.startTest();
        Map<String, Object> result = new XeroClient().listContacts('tenant-abc-123');
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/api.xro/2.0/Contacts'), mock.lastEndpoint);
        System.assert(result.containsKey('Contacts'));
    }

    @IsTest
    static void listAccounts_dispatchesGet() {
        XeroTestSupport.SingleResponseMock mock = arrange(
            '{"Accounts":[{"AccountID":"A1","Name":"Sales","Code":"200"}]}'
        );

        Test.startTest();
        Map<String, Object> result = new XeroClient().listAccounts('tenant-abc-123');
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/api.xro/2.0/Accounts'), mock.lastEndpoint);
        System.assert(result.containsKey('Accounts'));
    }

    @IsTest
    static void listPayments_dispatchesGet() {
        XeroTestSupport.SingleResponseMock mock = arrange(
            '{"Payments":[{"PaymentID":"P1","Amount":250.0}]}'
        );

        Test.startTest();
        Map<String, Object> result = new XeroClient().listPayments('tenant-abc-123');
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/api.xro/2.0/Payments'), mock.lastEndpoint);
        System.assert(result.containsKey('Payments'));
    }

    @IsTest
    static void listBankTransactions_dispatchesGet() {
        XeroTestSupport.SingleResponseMock mock = arrange(
            '{"BankTransactions":[{"BankTransactionID":"BT1","Total":100.0}]}'
        );

        Test.startTest();
        Map<String, Object> result = new XeroClient().listBankTransactions('tenant-abc-123');
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/api.xro/2.0/BankTransactions'), mock.lastEndpoint);
        System.assert(result.containsKey('BankTransactions'));
    }

    @IsTest
    static void getConnections_dispatchesGet() {
        XeroTestSupport.SingleResponseMock mock = arrange(
            '[{"tenantId":"tenant-abc-123","tenantName":"My Company"}]'
        );

        Test.startTest();
        List<Object> result = new XeroClient().getConnections();
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/connections'), mock.lastEndpoint);
        System.assertEquals(1, result.size());
    }

    @IsTest
    static void validationErrors_blankTenantId() {
        arrange('{}');
        XeroClient client = new XeroClient();

        try {
            client.listInvoices(null, null);
            System.assert(false, 'Expected XeroClient.ClientException');
        } catch (XeroClient.ClientException e) {
            System.assert(e.getMessage().contains('tenantId'));
        }

        try {
            client.listContacts('');
            System.assert(false, 'Expected XeroClient.ClientException');
        } catch (XeroClient.ClientException e) {
            System.assert(e.getMessage().contains('tenantId'));
        }

        try {
            client.listAccounts(null);
            System.assert(false, 'Expected XeroClient.ClientException');
        } catch (XeroClient.ClientException e) {
            System.assert(e.getMessage().contains('tenantId'));
        }

        try {
            client.listPayments('  ');
            System.assert(false, 'Expected XeroClient.ClientException');
        } catch (XeroClient.ClientException e) {
            System.assert(e.getMessage().contains('tenantId'));
        }
    }
}
